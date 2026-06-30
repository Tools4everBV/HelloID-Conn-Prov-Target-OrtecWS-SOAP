#################################################
# HelloID-Conn-Prov-Target-OrtecWS-SOAP-Enable
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
        Uri         = "$($actionContext.Configuration.BaseUrl)/CAIS/ApplicationIntegration/Development1?wsdl"
        Method      = 'POST'
        Body        = $envelope
        Headers     = $headers
        ContentType = 'application/soap+xml; charset=utf-8'
    }

    $response = Invoke-RestMethod @params
    $responseXML = $response.Envelope.Body.SendMessageResponse.SendMessageResult
    [xml]$xmlParsed = $responseXML
    $returnObjectobj = Convert-XmlNodeToPsObject $xmlParsed.DocumentElement
    if ($returnObjectobj.response.error){
        throw "The action could not be executed and failed with error: [$($returnObjectobj.response.error)], result: [$($returnObjectobj.response.result)] "
    }
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
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a Ortec-WS account exists'
    Write-Information 'Creating HelloID_GetUser Xml body'
    $splatHelloID_GetUserXmlBody = New-OrtecSoapXMLBody @{
        psk        = $actionContext.Configuration.Psk
        parameters = @{
            employeeNumber = $actionContext.References.Account
        }
    }

    Write-Information 'Invoking Ortec-WS HelloID_GetUser command'
    $helloID_GetUserResponse = Invoke-OrtecSoapRequest -CommandName 'HelloID_GetUser' -Body $splatHelloID_GetUserXmlBody
    $correlatedAccount = $helloID_GetUserResponse.users.user

    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'EnableAccount'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'EnableAccount' {
            Write-Information "Enabling Ortec-WS account with accountReference: [$($actionContext.References.Account)]"
            Write-Information 'Creating HelloID_UpdateUser Xml body'
            $splatHelloID_UpdateUserXmlBody = New-OrtecSoapXMLBody @{
                psk  = $actionContext.Configuration.Psk
                User = @{
                    employeeNumber = $actionContext.References.Account
                    userName       = $correlatedAccount.userName
                    action         = 'activate'
                }
            }
            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-OrtecSoapRequest -CommandName 'HelloID_UpdateUser' -Body $splatHelloID_UpdateUserXmlBody
            }
            else {
                Write-Information "[DryRun] Enable Ortec-WS account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Enable account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Ortec-WS account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Ortec-WS account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    $auditLogMessage = "Could not enable Ortec-WS account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}