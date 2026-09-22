#######################################################################
# HelloID-Conn-Prov-Target-OrtecWS-SOAP-ImportPermissions-Authorization
# PowerShell V2
#######################################################################

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
    try {
        $response = Invoke-restmethod @params
        $responseXML = $response.Envelope.Body.SendMessageResponse.SendMessageResult

        [xml]$xmlParsed = $responseXML
        $returnObjectobj = Convert-XmlNodeToPsObject $xmlParsed.DocumentElement
        Write-Output $returnObjectobj
    }
    catch {
        $ex = $PSItem

        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-OrtecWSError -ErrorObject $ex

            $auditMessage = "$($ex.Exception.Message)"        
            $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorObj.ErrorDetails)"
        }
        else {
            $auditMessage = "$($ex.Exception.Message)"
            $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        }

        Write-Warning "$([System.Net.WebUtility]::HtmlDecode($warningMessage))"


        throw $auditMessage
    }

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

function Resolve-OrtecWSError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($httpErrorObj.ErrorDetails)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting Ortec-WS permission entitlement import'
    Write-Information 'Creating HelloID_GetAuthorizations Xml body'
    $splatHelloID_GetAuthorizationsXmlBody = New-OrtecSoapXMLBody @{
        psk        = $actionContext.Configuration.Psk
        parameters = @{
            roleId = '0'
        }
    }

    Write-Information 'Invoking Ortec-WS HelloID_GetAuthorizations command'
    $helloID_GetAuthorizationsResponse = Invoke-OrtecSoapRequest -CommandName 'HelloID_GetAuthorizations' -Body $splatHelloID_GetAuthorizationsXmlBody
    $allRoles = $helloID_GetAuthorizationsResponse.roles.role

    Write-Information 'Creating HelloID_GetUserAuthorizations Xml body'
    $splatHelloID_GetUserAuthorizationsXmlBody = New-OrtecSoapXMLBody @{
        psk        = $actionContext.Configuration.Psk
        parameters = @{
            employeeNumber = '0'
        }
    }

    Write-Information 'Invoking Ortec-WS HelloID_GetUserAuthorizations command'
    $helloID_GetUserAuthorizations = Invoke-OrtecSoapRequest -CommandName 'HelloID_GetUserAuthorizations' -Body $splatHelloID_GetUserAuthorizationsXmlBody
    $allAuthorizations = $helloID_GetUserAuthorizations.users.user

    Write-Information 'Building role to accounts list'
    $roleToAccounts = @()
    foreach ($user in $allAuthorizations) {
        if ($user.Roles.GetType().name -eq "String") {
            continue
        }
        foreach ($role in @($user.Roles)) {
            $roleId = [string]$role.roleId

            $entry = $roleToAccounts | Where-Object { $_.roleId -eq $roleId }
            if (-not $entry) {
                $entry = [pscustomobject]@{
                    roleId   = $roleId
                    roleName = $null
                    members  = @()
                }
                $roleToAccounts += $entry
            }
            $entry.members += $user.employeeNumber
        }
    }

    Write-Information 'Adding role names to the role to accounts list'
    foreach ($role in $allRoles) {
        $entry = $roleToAccounts | Where-Object { $_.roleId -eq [string]$role.roleId }
        if ($entry) {
            $entry.roleName = $role.roleName
        }
    }

    foreach ($role in $roleToAccounts) {
        $permission = @{
            PermissionReference = @{
                Reference = $role.roleId
            }
            Description         = $role.roleId
            DisplayName         = $role.roleName
            AccountReferences   = $null
        }

        $batchSize = 500
        for ($i = 0; $i -lt ($role.members | Measure-Object).Count; $i += $batchSize) {
            $permission.AccountReferences = $role.members[$i..([Math]::Min($i + $batchSize - 1, $role.members.Count - 1))]
            Write-Output $permission
        }
    }
    Write-Information 'Ortec-WS permission entitlement import completed'
}
catch {
    $ex = $PSItem
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    Write-Error "Could not import Ortec-WS permission entitlements. Error: $($ex.Exception.Message)"
}