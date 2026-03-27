##########################################################
# HelloID-Conn-Prov-Target-FreshService-Resources-Group
# PowerShell V2
##########################################################

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
#endregion

try {
    Write-Information "Creating [$($resourceContext.SourceData.Count)] resources"

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $($actionContext.Configuration.authorizationToken)")
    $headers.Add("Content-Type", "application/json; charset=utf-8")
    $headers.Add("Accept", "application/json; charset=utf-8")


    $page = 1
    $pagesize = 100
    $responseDepartments = [System.Collections.Generic.List[PSCustomObject]]::new()
    do {
        $splatGetDepartments = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/departments?per_page=$pagesize&page=$page"
            Headers = $headers
            Method  = "GET"
        }
        $responseDepartmentsPage = (Invoke-RestMethod @splatGetDepartments).departments
        $responseDepartments += $responseDepartmentsPage 

        $departmentCount = ($responseDepartmentsPage | Measure-Object).count
        $page++
    } while (
        $departmentCount -lt $pagesize
    )
    
    foreach ($department in $resourceContext.SourceData) {
        try {
            <# Resource creation preview uses a timeout of 30 seconds while actual run has timeout of 10 minutes #>
            $targetDepartment = ($responseDepartments | Where-Object -Property name -eq $department)
            if ($null -eq $targetDepartment) {
                $Body = @{
                    name = "$($department)"
                } | ConvertTo-Json 
                
                $splatAddDepartmentRequest = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/departments"
                    Headers = $headers
                    Method  = "POST"
                    Body    = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($Body)
                }

                if (-not($actionContext.DryRun -eq $True)) {
                    Write-Information "Create [$($department)] FreshService department"

                    $responseAddDepartmentRequest = Invoke-RestMethod @splatAddDepartmentRequest
                }
                else {
                    Write-Information "[DryRun] Create FreshService [$($department)] department, will be executed during enforcement"
                }

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CreateResource'
                        Message = "Created department: [$($department)], was successful. Id is: [$($responseAddDepartmentRequest.department.id)]"
                        IsError = $false
                    })
            }           
        }
        catch {
            $outputContext.Success = $false
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-FreshServiceError -ErrorObject $ex
                $auditLogMessage = "Could not create FreshService resource. Error: $($errorObj.FriendlyMessage)"
                Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            }
            else {
                $auditLogMessage = "Could not create FreshService resource. Error: $($ex.Exception.Message)"
                Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $true
                })
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FreshServiceError -ErrorObject $ex
        $auditLogMessage = "Could not create FreshService resource. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create FreshService resource. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
