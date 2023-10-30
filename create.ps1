#######################################################################
# HelloID-Conn-Prov-Target-Freshservice-Employee-Onboarding
#
# Version: 1.0.1
#######################################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

$location = $p.PrimaryContract.Location
$department = $p.PrimaryContract.Department

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

$skipCreation = $config.skipCreation

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

function New-Name {
    [cmdletbinding()]
    Param (
        [object]$person
    )
    try {
        $suffix = "";
        $givenname = if ([string]::IsNullOrEmpty($person.Name.Nickname)) { $person.Name.Initials.Substring(0, 1) }else { $person.Name.Nickname }
        $FamilyNamePrefix = $person.Name.FamilyNamePrefix
        $FamilyName = $person.Name.FamilyName           
        $PartnerNamePrefix = $person.Name.FamilyNamePartnerPrefix
        $PartnerName = $person.Name.FamilyNamePartner 
        $convention = $person.Name.Convention
        $Surname = ""    

        switch ($convention) {
            "B" {
                $Surname += if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix + " " }
                $Surname += $FamilyName

                $prefix = if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix }
            }
            "P" {
                $Surname += if (-NOT([string]::IsNullOrEmpty($PartnerNamePrefix))) { " " + $PartnerNamePrefix }
                $Surname += $PartnerName

                $prefix = if (-NOT([string]::IsNullOrEmpty($PartnerNamePrefix))) { $PartnerNamePrefix }
            }
            "BP" {
                $Surname += if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix + " " } 
                $Surname += $FamilyName + " - "
                $Surname += if (-NOT([string]::IsNullOrEmpty($PartnerNamePrefix))) { $PartnerNamePrefix + " " }
                $Surname += $PartnerName

                $prefix = if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix }
            }
            "PB" {
                $Surname += if (-NOT([string]::IsNullOrEmpty($PartnerNamePrefix))) { $PartnerNamePrefix + " " }
                $Surname += $PartnerName + " - "
                $Surname += if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix + " " }
                $Surname += $FamilyName

                $prefix = if (-NOT([string]::IsNullOrEmpty($PartnerNamePrefix))) { $PartnerNamePrefix }
            }
            Default {
                $Surname += if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix + " " }
                $Surname += $FamilyName

                $prefix = if (-NOT([string]::IsNullOrEmpty($FamilyNamePrefix))) { $FamilyNamePrefix }                           
            }
        }      

        $output = [PSCustomObject]@{
            prefixes = $prefix
            surname  = $Surname
        }
        Write-Output $output
            
    }
    catch {
        throw("An error was found in the name convention algorithm: $($_.Exception.Message): $($_.ScriptStackTrace)")
    } 
}

function format-date {
    [CmdletBinding()]
    Param
    (
        [string]$date,
        [string]$InputFormat,
        [string]$OutputFormat
    )
    try {
        if (-NOT([string]::IsNullOrEmpty($date))) {    
            $dateString = get-date([datetime]::ParseExact($date, $InputFormat, $null)) -Format($OutputFormat)
        }
        else {
            $dateString = $null
        }

        return $dateString
    }
    catch {
        throw("An error was thrown while formatting date: $($_.Exception.Message): $($_.ScriptStackTrace)")
    }
}

#endregion

# Begin
try {    
    # Account mapping
    $account = @{
        fields = @{
            cf_employee_name    = $p.Name.NickName
            cf_employee_surname = (New-Name -person $p).surname
            cf_job_title        = $p.PrimaryContract.title.Name
            cf_date_of_joining  = format-date -date $p.primarycontract.startdate -InputFormat 'MM/dd/yyyy hh:mm:ss' -OutputFormat "yyyy-MM-dd"
            actor_2             = $p.PrimaryManager.email
            cf_department       = $p.PrimaryContract.Department.DisplayName
            cf_cost_center      = [int]$p.PrimaryContract.CostCenter.ExternalId
            cf_location         = $null #Added later in the script
            cf_leader_position  = "No"
        }
    }

    if (-NOT $skipCreation) {

        $bytes = [System.Text.Encoding]::ASCII.GetBytes("$($config.authorizationToken)")
        $base64 = [System.Convert]::ToBase64String($bytes)

        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Basic $($base64)")

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
            Uri     = Resolve-url -Url "$($config.BaseUrl)/api/v2/requesters?query=`"primary_email:'$($account.Fields.actor_2)'`""
            Headers = $headers
            Method  = "GET"
        }
        $actorId = (Invoke-RestMethod @splatGetRequester).requesters.id
        if ($null -eq $actorId) {
            $splatGetAgent = @{
                Uri     = Resolve-url -Url "$($config.BaseUrl)/api/v2/agents?query=`"email:'$($account.Fields.actor_2)'`""
                Headers = $headers
                Method  = "GET"
            }
            $actorId = (Invoke-RestMethod @splatGetAgent).agents.id
            if ($null -eq $actorId) {
                throw "Actor: [$($account.Fields.actor_2)] does not exist in Freshservice"
            }
        }

        # Add a warning message showing what will happen during enforcement
        if ($dryRun -eq $true) {
            Write-Warning "[DryRun] create Freshservice onboarding request for: [$($p.DisplayName)], will be executed during enforcement"
            Write-Warning "[DryRun] body: $($account | ConvertTo-Json -Depth 2)"
        }

        # Process
        if (-not($dryRun -eq $true)) {
            Write-Verbose 'Creating and correlating Freshservice account'
            $jsonAccount = ($account | ConvertTo-Json -Depth 2)

            # $encodedBytes = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($jsonAccount)

            $splatAddOnboardingRequest = @{
                Uri         = "$($config.BaseUrl)/api/v2/onboarding_requests"
                Headers     = $headers
                Method      = "POST"
                Body        = $jsonAccount
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
    else {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Creating onboarding requests are disabled"
                IsError = $false
            })

        $success = $true
    }
}
catch {
    write-error "$($_.ErrorDetails.Message)"
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
        ExportData       = @{
            requestID = $responseAddOnboardingRequest.onboarding_request.id
        }
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}