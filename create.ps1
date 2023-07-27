#######################################################################
# HelloID-Conn-Prov-Target-Freshservice-Employee-Onboarding
#
# Version: 1.0.0
#######################################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

$location = $p.PrimaryContract.Location
$department = $p.PrimaryContract.Department
$manager = $p.PrimaryManager

# Account mapping
$account = @{
    Fields = @{
        cf_employee_name    = $p.Name.GivenName
        cf_employee_surname = $p.Name.FamilyName
        cf_job_title        = $p.PrimaryContract.Department.DisplayName
        cf_date_of_joining  = (Get-Date -Format "yyyy-MM-dd")
        actor_2             = $manager.Email
        cf_department       = "" #Added later in the script
        cf_cost_center      = $p.PrimaryContract.CostCenter.ExternalId
        cf_location         = "" #Added later in the script
        cf_leader_position  = "No"
    }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
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

# Begin
try {
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $($config.authorizationToken)")

    $splatGetLocations = @{
        Uri     = Resolve-url -Url "$($config.BaseUrl)/api/v2/locations?query=`"name:'$($location.name)'`""
        Headers = $headers
        Method  = "GET"
    }
    $responseLocations = Invoke-RestMethod @splatGetLocations
    if ($null -eq $responseLocations) {
        throw "Location: [$($location.Name)] does not exist in Freshservice"
    }
    $account.Fields.cf_location = $responseLocations.locations.id

    $splatGetDepartments = @{
        Uri     = Resolve-url -Url "$($config.BaseUrl)/api/v2/departments?query=`"name:'$($department.DisplayName)'`""
        Headers = $headers
        Method  = "GET"
    }
    $responseDepartments = Invoke-RestMethod @splatGetDepartments 
    if ($null -eq $responseDepartments) {
        throw "Department: [$($department.Name)] does not exist in Freshservice"
    }
    $account.Fields.cf_department = $responseDepartments.departments.name

    $splatGetRequester = @{
        Uri     = Resolve-url -Url "$($config.BaseUrl)/api/v2/requesters?query=`"primary_email:'$($manager.Email)'`""
        Headers = $headers
        Method  = "GET"
    }
    $actorId = (Invoke-RestMethod @splatGetRequester).requesters.id
    if ($null -eq $actorId) {
        $splatGetAgent = @{
            Uri     = Resolve-url -Url "$($config.BaseUrl)/api/v2/agents?query=`"email:'$($manager.Email)'`""
            Headers = $headers
            Method  = "GET"
        }
        $actorId = (Invoke-RestMethod @splatGetAgent).agents.id
        if ($null -eq $actorId) {
            throw "Actor: [$($manager.Email)] does not exist in Freshservice"
        }
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] create Freshservice onboarding request for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        Write-Verbose 'Creating and correlating Freshservice account'
        $jsonAccount = ($account | ConvertTo-Json -Depth 2)
        $encodedBytes = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($jsonAccount)

        $splatAddOnboardingRequest = @{
            Uri         = "$($config.BaseUrl)/api/v2/onboarding_requests"
            Headers     = $headers
            Method      = "POST"
            Body        = $encodedBytes
            ContentType = "application/json; charset=utf-8"
        }
        $responseAddOnboardingRequest = Invoke-RestMethod @splatAddOnboardingRequest 
                
        $auditLogs.Add([PSCustomObject]@{
                Message = "Create onboarding request was successful. Id is: [$($responseAddOnboardingRequest.onboarding_request.id)]"
                IsError = $false
            })

        $success = $true
        break
    }       
}
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-FreshserviceError -ErrorObject $ex
        $auditMessage = "Could not create Freshservice onboarding request. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create Freshservice onboard request. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
}
finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
