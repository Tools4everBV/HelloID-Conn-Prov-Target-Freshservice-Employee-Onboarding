#################################################
# HelloID-Conn-Prov-Target-FreshService-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-FreshServiceError {
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
            $httpErrorObj.FriendlyMessage = ($httpErrorObj.FriendlyMessage | ConvertFrom-Json).error_description
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            Write-Warning $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}

function Resolve-url {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $url
    )
    process {
        try {
            $url = $url.Replace('&', '%26')
        }
        catch {
            throw "Could not resolve url"
        }
        Write-Output $url
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $($actionContext.Configuration.authorizationToken)")

    # Validation    
    $auditLogsValidation = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ([string]::IsNullOrEmpty($actionContext.Data.cf_location)) {
        $auditLogsValidation.Add([PSCustomObject]@{
                Message = 'cf_location is empty, make sure the property has a value'
                IsError = $true
            })
    }
    else {
        $splatGetLocations = @{
            Uri     = Resolve-url -Url "$($actionContext.Configuration.BaseUrl)/api/v2/locations?query=`"name:'$($actionContext.Data.cf_location)'`""
            Headers = $headers
            Method  = "GET"
        }
        $responseLocations = Invoke-RestMethod @splatGetLocations
        if ($null -eq $responseLocations) {
            $auditLogsValidation.Add([PSCustomObject]@{
                    Message = "Location: [$($actionContext.Data.cf_location)] does not exist in FreshService"
                    IsError = $true
                })
        }
        $outputContext.Data.cf_location = $responseLocations.locations.id
    }
    
    if ([string]::IsNullOrEmpty($actionContext.Data.cf_department)) {
        $auditLogsValidation.Add([PSCustomObject]@{
                Message = 'cf_department is empty, make sure the property has a value'
                IsError = $true
            })            
    }
    else {
        $splatGetDepartments = @{
            Uri     = Resolve-url -Url "$($actionContext.Configuration.BaseUrl)/api/v2/departments?query=`"name:'$($actionContext.Data.cf_department)'`""
            Headers = $headers
            Method  = "GET"
        }
        $responseDepartments = Invoke-RestMethod @splatGetDepartments 
        if ($null -eq $responseDepartments) {
            $auditLogsValidation.Add([PSCustomObject]@{
                    Message = "Department: [$($actionContext.Data.cf_department)] does not exist in FreshService"
                    IsError = $true
                })
        }
        $outputContext.Data.cf_department = $responseDepartments.departments.name
    }
    
    if ([string]::IsNullOrEmpty($actionContext.Data.actor_2)) {
        $auditLogsValidation.Add([PSCustomObject]@{
                Message = 'actor_2 is empty, make sure the property has a value'
                IsError = $true
            }) 
    }
    else {
        $splatGetRequester = @{
            Uri     = Resolve-url -Url "$($actionContext.Configuration.BaseUrl)/api/v2/requesters?query=`"primary_email:'$($actionContext.Data.actor_2)'`""
            Headers = $headers
            Method  = "GET"
        }
        $actorId = (Invoke-RestMethod @splatGetRequester).requesters.id
        if ($null -eq $actorId) {
            $splatGetAgent = @{
                Uri     = Resolve-url -Url "$($actionContext.Configuration.BaseUrl)/api/v2/agents?query=`"email:'$($actionContext.Data.actor_2)'`""
                Headers = $headers
                Method  = "GET"
            }
            $actorId = (Invoke-RestMethod @splatGetAgent).agents.id
            if ($null -eq $actorId) {
                $auditLogsValidation.Add([PSCustomObject]@{
                        Message = "Actor: [$($actionContext.Data.actor_2)] does not exist in FreshService"
                        IsError = $true
                    })
            }
        }
    }

    if ($auditLogsValidation.count -gt 0) {
        $outputContext.AuditLogs.AddRange($auditLogsValidation)
        throw 'Validation Error'
    }

    $actionContext.Data.cf_cost_center = [int]$actionContext.Data.cf_cost_center
    $body = @{
        Fields = $actionContext.Data
    } | ConvertTo-Json -Depth 10
    $encodedBytes = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($body)

    $splatAddOnboardingRequest = @{
        Uri         = "$($config.BaseUrl)/api/v2/onboarding_requests"
        Headers     = $headers
        Method      = "POST"
        Body        = $encodedBytes
        ContentType = "application/json; charset=utf-8"
    }

    if (-not($actionContext.DryRun -eq $true)) {
        Write-Information 'Onboarding FreshService account'

        $createdAccount = Invoke-RestMethod @splatAddOnboardingRequest 
            
        $outputContext.Data = ($createdAccount.onboarding_request | Select-Object $outputContext.Data.PSObject.Properties.Name)
        $outputContext.AccountReference = $createdAccount.onboarding_request.id
    }
    else {
        Write-Information '[DryRun] Onboarding FreshService account, will be executed during enforcement'
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Onboarding account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if (-not $ex.Exception.message -eq 'Validation Error') {
        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-FreshServiceError -ErrorObject $ex
            $auditLogMessage = "Could not onboard or correlate FreshService account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
            Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        }
        else {
            $auditLogMessage = "Could not onboard or correlate FreshService account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
            Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        }
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $auditLogMessage
                IsError = $true
            })
    }
}