#################################################
# HelloID-Conn-Prov-Target-OrtecWS-SOAP-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a Ortec-WS account exists where $correlationField is: [$correlationValue]"
        Write-Information 'Creating HelloID_GetUser Xml body'
        $splatHelloID_GetUserXmlBody = New-OrtecSoapXMLBody @{
            psk        = $actionContext.Configuration.Psk
            parameters = @{
                employeeNumber = $correlationValue
            }
        }
        Write-Information 'Invoking Ortec-WS HelloID_GetUser command'
        $helloID_GetUserResponse = Invoke-OrtecSoapRequest -CommandName 'HelloID_GetUser' -Body $splatHelloID_GetUserXmlBody
        $correlatedAccount = $helloID_GetUserResponse.users.user | Select-Object -Property userName, employeeNumber
    } else {
        throw 'Correlation is not enabled for this connector, correlation is required must be enabled'
    }

    if ($null -eq $correlatedAccount) {
        $lifecycleProcess = 'CreateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }
    else {
        $lifecycleProcess = 'CorrelateAccount'
    }

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            Write-Information 'Creating HelloID_AddUser Xml body'
            $splatHelloID_AddUserXmlBody = New-OrtecSoapXMLBody @{
                psk  = $actionContext.Configuration.Psk
                User = @{
                    employeeNumber = $actionContext.Data.employeeNumber
                    userName       = $actionContext.Data.userName
                }
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Ortec-WS account'
                Write-Information 'Invoking Ortec-WS HelloID_AddUser command'
                $helloID_AddUserResponse = Invoke-OrtecSoapRequest -CommandName 'HelloID_AddUser' -Body $splatHelloID_AddUserXmlBody
                $result = $helloID_AddUserResponse.Response.result
                if ($result -eq 'ACK') {

                    # Retrieve the created account
                    Write-Information 'Creating HelloID_GetUser Xml body'
                    $splatHelloID_GetUserXmlBody = New-OrtecSoapXMLBody @{
                        psk        = $actionContext.Configuration.Psk
                        parameters = @{
                            employeeNumber = $correlationValue
                        }
                    }
                    Write-Information 'Invoking Ortec-WS HelloID_GetUser command'
                    $helloID_GetUserResponse = Invoke-OrtecSoapRequest -CommandName 'HelloID_GetUser' -Body $splatHelloID_GetUserXmlBody
                    $createdAccount = $helloID_GetUserResponse.users.user | Select-Object -Property userName, employeeNumber
                    if ($null -eq $createdAccount) {
                        Write-Information 'Account was created but could not be retrieved. An employee account does not exist. Therefore, the account was created but could no be attached to an existing employee in Ortec-WS. Please verify if an employee account for this user exists in Ortec-WS'
                    }
                } elseif ($result -eq 'NACK') {
                    throw "Ortec-WS responded with NACK, the account was not created. Response: [$($helloID_AddUserResponse.repsonse.error)]"
                }
                else {
                    throw "Ortec-WS responded with an unknown response: [$($helloID_AddUserResponse.repsonse.error)]"
                }
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.employeeNumber
            }
            else {
                Write-Information '[DryRun] Create and correlate Ortec-WS account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Ortec-WS account'
            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.employeeNumber
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    $auditLogMessage = "Could not create or correlate Ortec-WS account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}