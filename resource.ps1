#############################################
# HelloID-Conn-Prov-Target-Freshservice-Employee-Onboarding
#
# Version: 1.0.0
#############################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$rRef = $resourceContext | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
 
#region functions
function Resolve-FreshserviceError {
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
        if ($ErrorObject.ErrorDetails) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
            $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails
        }
        elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {         
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if (-not([string]::IsNullOrWhiteSpace($streamReaderResponse))) {
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = $streamReaderResponse
            }
        }
        try {
            $httpErrorObj.FriendlyMessage = ($httpErrorObj.FriendlyMessage | ConvertFrom-Json).error_description
        }
        catch {
            #displaying the old message if an error occurs during an API call, as the error is related to the API call and not the conversion process to JSON.
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Process
    if (-not ($dryRun -eq $true)) {
        Write-Verbose "Creating [$($rRef.SourceData.count)] resources"
        <# Resource creation preview uses a timeout of 30 seconds
            while actual run has a timeout of 10 minutes #>
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Basic $($config.authorizationToken)")
        $headers.Add("Content-Type", "application/json; charset=utf-8")
        $headers.Add("Accepts", "application/json; charset=utf-8")

        $splatGetDepartments = @{
            Uri     = "$($config.BaseUrl)/api/v2/departments"
            Headers = $headers
            Method  = "GET"
        }
        $responseDepartments = (Invoke-RestMethod @splatGetDepartments).departments

        foreach ($department in $rRef.sourceData) {
            $targetDepartment = ($responseDepartments | Where-Object -Property name -eq $orgunit.DepartmentCode)
            if ($null -eq $targetDepartment) {
                $Body = @{
                    name = "$($department)"
                }
                $jsonBody = ($Body | ConvertTo-Json  )
                $encodedBytes = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($jsonBody)
                
                $splatAddDepartmentRequest = @{
                    Uri     = "$($config.BaseUrl)/api/v2/departments"
                    Headers = $headers
                    Method  = "POST"
                    Body    = $encodedBytes
                }
                $responseAddDepartmentRequest = Invoke-RestMethod @splatAddDepartmentRequest

                $auditLogs.Add([PSCustomObject]@{
                        Message = "Created department [$($responseAddDepartmentRequest.department.name)], was successful. Id is: [$($responseAddDepartmentRequest.department.id)]"
                        IsError = $false
                    })
            }           
        }
        $success = $true
    }
}
# End
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FreshserviceError -ErrorObject $ex
        $auditMessage = "Could not create Freshservice department. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create Freshservice department. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}