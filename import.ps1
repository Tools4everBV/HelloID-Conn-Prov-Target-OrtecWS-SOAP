#################################################
# HelloID-Conn-Prov-Target-OrtecWS-SOAP-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function New-OrtecSoapXMLBody {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]
        $Data
    )

    $xml = [System.Xml.XmlDocument]::new()
    $root = $xml.CreateElement("XML")
    $xml.AppendChild($root) | Out-Null

    foreach ($key in $Data.Keys) {
        $value = $Data[$key]

        if ($value -is [hashtable]) {
            $parent = $xml.CreateElement($key)

            foreach ($subKey in $value.Keys) {
                $child = $xml.CreateElement($subKey)
                $child.InnerText = $value[$subKey]
                $parent.AppendChild($child) | Out-Null
            }

            $root.AppendChild($parent) | Out-Null
        }
        else {
            $node = $xml.CreateElement($key)
            $node.InnerText = $value
            $root.AppendChild($node) | Out-Null
        }
    }

    $xml.OuterXml
}

function Invoke-OrtecSoapRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $CommandName,

        [Parameter(Mandatory)]
        [string]
        $Body
    )

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.ApiUsername):$($actionContext.Configuration.ApiPassword)")))")
    $headers.Add('SOAPAction', '"http://www.Ortec.com/CAIS/IApplicationIntegrationService/SendMessage"')

    $envelope = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
    xmlns:cais="http://www.ortec.com/CAIS"
    xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">
    <soap:Header xmlns:wsa="http://www.w3.org/2005/08/addressing">
        <wsa:Action>http://www.ortec.com/CAIS/IApplicationIntegrationService/SendMessage</wsa:Action>
        <wsa:ReplyTo>
            <wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address>
        </wsa:ReplyTo>
    </soap:Header>
    <soap:Body>
        <cais:SendMessage>
            <cais:message>
                <![CDATA[
$Body
                ]]>
            </cais:message>
            <cais:commandName>$CommandName</cais:commandName>
        </cais:SendMessage>
    </soap:Body>
</soap:Envelope>
"@

    $params = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)"
        Method      = 'POST'
        Body        = $envelope
        Headers     = $headers
        ContentType = 'application/soap+xml; charset=utf-8'
    }

    $response = Invoke-RestMethod @params
    $responseXML = $response.Envelope.Body.SendMessageResponse.SendMessageResult
    [xml]$xmlParsed = $responseXML
    $returnObjectobj = Convert-XmlNodeToPsObject $xmlParsed.DocumentElement
    Write-Output $returnObjectobj
}

function Convert-XmlNodeToPsObject {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node
    )

    if ($Node.ChildNodes.Count -eq 0) {
        return $Node.InnerText
    }

    $props = @{}

    foreach ($child in $Node.ChildNodes) {
        $name = $child.Name
        if ($child.ChildNodes.Count -gt 1 -or ($child.ChildNodes.Count -eq 1 -and $child.FirstChild.NodeType -eq 'Element')) {
            if (-not $props.ContainsKey($name)) {
                $props[$name] = @()
            }
            $props[$name] += Convert-XmlNodeToPsObject $child
        }
        else {
            $props[$name] = $child.InnerText
        }
    }
    [PSCustomObject]$props
}
#endregion

try {
    Write-Information 'Starting OrtecWS account entitlement import'
    Write-Information 'Creating HelloID_GetUser Xml body'
    $splatHelloID_GetUserXmlBody = New-OrtecSoapXMLBody @{
        psk        = $actionContext.Configuration.Psk
        parameters = @{
            employeeNumber = '0'
        }
    }

    Write-Information 'Invoking Ortec-WS HelloID_GetUser command'
    $helloID_GetUserResponse = Invoke-OrtecSoapRequest -CommandName 'HelloID_GetUser' -Body $splatHelloID_GetUserXmlBody
    $importedAccounts = $helloID_GetUserResponse.users.user
    foreach ($importedAccount in $importedAccounts) {
        # Making sure only fieldMapping fields are imported
        $data = @{}
        foreach ($field in $actionContext.ImportFields) {
            $data[$field] = $importedAccount.$field
        }

        # Set Enabled based on importedAccount status
        $isEnabled = $false
        if ($importedAccount.status -eq 'active') {
            $isEnabled = $true
        }

        # Make sure the displayName has a value
        $displayName = $importedAccount.userName
        if ([string]::IsNullOrEmpty($displayName)) {
            $displayName = $importedAccount.employeeNumber
        }

        # Make sure the userName has a value
        if ([string]::IsNullOrWhiteSpace($importedAccount.UserName)) {
            $importedAccount.UserName = $importedAccount.employeeNumber
        }

        # Return the result
        Write-Output @{
            AccountReference = $importedAccount.employeeNumber
            DisplayName      = $displayName
            UserName         = $importedAccount.UserName
            Enabled          = $isEnabled
            Data             = $data
        }
    }

    Write-Information 'OrtecWS account entitlement import completed'
}
catch {
    $ex = $PSItem
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    Write-Error "Could not import OrtecWS account entitlements. Error: $($ex.Exception.Message)"
}
