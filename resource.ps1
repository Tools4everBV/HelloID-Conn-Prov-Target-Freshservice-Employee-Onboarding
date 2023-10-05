#############################################
# HelloID-Conn-Prov-Target-Freshservice-Employee-Onboarding
#
# Version: 1.0.1
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

    Write-Verbose "Creating [$($rRef.SourceData.count)] resources"
    <# Resource creation preview uses a timeout of 30 seconds
            while actual run has a timeout of 10 minutes #>
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$($config.authorizationToken)")
    $base64 = [System.Convert]::ToBase64String($bytes)
    $headers.Add("Authorization", "Basic $($base64)")  

    $headers.Add("Content-Type", "application/json; charset=utf-8")
    $headers.Add("Accepts", "application/json; charset=utf-8")

    #get departments:
    $page = 0
    $pagesize = 100
    $responseDepartments = [System.Collections.Generic.List[PSCustomObject]]::new()

    do {
        $page++
        $splatGetDepartments = @{
            Uri     = "$($config.BaseUrl)/api/v2/departments?per_page=$pagesize&page=$page"
            Headers = $headers
            Method  = "GET"
        }
        $responseDepartmentsPage = (Invoke-RestMethod @splatGetDepartments).departments
        $responseDepartments += $responseDepartmentsPage 

        $departmentCount = ($responseDepartmentsPage | Measure-Object).count
            
    } until ($page -gt 10 -OR $departmentCount -lt $pagesize)


    Write-Verbose -verbose "count: $(($responseDepartments | measure-object).count)"

    foreach ($department in $rRef.sourceData) {

        $targetDepartment = ($responseDepartments | Where-Object -Property name -eq $department.DisplayName)
        if ($null -eq $targetDepartment) {
            $Body = @{
                name = "$($department.DisplayName)"
            }
            $jsonBody = ($Body | ConvertTo-Json  )
            $encodedBytes = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($jsonBody)
                
            $splatAddDepartmentRequest = @{
                Uri     = "$($config.BaseUrl)/api/v2/departments"
                Headers = $headers
                Method  = "POST"
                Body    = $encodedBytes
            }
            if (-not ($dryRun -eq $true)) {
                $responseAddDepartmentRequest = Invoke-RestMethod @splatAddDepartmentRequest
            }

            $auditLogs.Add([PSCustomObject]@{
                    Message = "Created department $($department.DisplayName) [$($department.ExternalID)] was successful. Id is: [$($responseAddDepartmentRequest.department.id)]"
                    IsError = $false
                })
        }
        else {
            Write-Verbose "Skipped creation - department [$($department.DisplayName)] found with ID: $($targetDepartment.id) "

        }    
    }
    $success = $true
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