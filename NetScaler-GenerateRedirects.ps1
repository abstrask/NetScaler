<#

.SYNOPSIS
    Generates a NetScaler batch configuration file, for configuring redirects based on a list of redirect rules.

    Request URLs containing wilcards ("*") are considered fallback redirect rules, and will be the last rules to be added
   
.PARAMETER CsvPath
    Required. The path to the CSV file specifying the redirect rules.
    - Headers must be: "Domain", "RequestUrl", "RedirectUrl"
    - Fields must be semicolon-separated (or manually change character for the 'Import-Csv' command)
    - The file format must be in UTF8 (Excel: Save as "CSV UTF-8")
    - No blank lines (could probably easily be ignored in a future version)
    - RequestUrls are automatically URL encoded - otherwise the NetScaler rules may not work

.PARAMETER RedirUrlPrefix
    Required. The text string to prefix the redirected URLs with (before "RedirectUrl"), e.g. "https://www.newdomain.tld" or "http://www.anotherdomain.tld".
    
.PARAMETER HttpVserver
    Required. The name of the content switch virtual server for HTTP requests

.PARAMETER HttpsVserver
    Required. The name of the content switch virtual server for HTTPS requests

.PARAMETER SpecificRuleNumberBegin
    Optional. The starting number for naming the specific (not containing wildcards) responder actions and policies, e.g. RespAct_1000. Defaults to 1000.

.PARAMETER FallbackRuleNumberBegin
    Optional. The starting number for naming the fallback (wildcard) responder actions and policies, e.g. RespPol_9000. Defaults to 9000.

.PARAMETER RuleNumberIncrement
    Optional. The number to increment by for each rule name, e.g. RespPol_1000, RespPol_1010. Defaults to 1.

.PARAMETER PriorityBegin
    Optional. The starting priority for the policy bindings. Defaults to 100, to leave room for higher priority bindings.

.PARAMETER PriorityIncrement
    Optional. The number to increment the priority of each policy binding by. Defaults to 10, to leave room for other bindings inbetween.
   
.PARAMETER OutputPath
    Optional. The path where batch files are output to. Defaults to current working directory.

.EXAMPLE
    .\NetScaler-GenerateRedirects.ps1 -CsvPath .\Redirects_Example.csv -RedirUrlPrefix "https://www.newdomain.tld/" -HttpVserver CSW_VIP_HTTP-Redirects -HttpsVserver CSW_VIP_HTTPS-Redirects
    "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/?$#)" ==> https://www.newdomain.tld/brand/new/path/
    "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/sub-path/?$#)" ==> https://www.newdomain.tld/brand/new/path/
    "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/sub-path/old-page/?$#)" ==> https://www.newdomain.tld/brand/new/path/new-page
    "HTTP.REQ.URL.EQ(\"/\")" ==> https://www.newdomain.tld/new/path/
    "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).STARTSWITH(\"/some-old-path/\")" ==> https://www.newdomain.tld/brand/new/path/
    NetScaler batch configuration output: C:\code\private\NetScaler-GenerateRedirects\redirects_20181205-125626.txt

.EXAMPLE
    .\NetScaler-GenerateRedirects.ps1 -CsvPath .\Redirects_Example.csv -RedirUrlPrefix "https://www.newdomain.tld/" -HttpVserver CSW_VIP_HTTP-Redirects -HttpsVserver CSW_VIP_HTTPS-Redirects -SpecificRuleNumberBegin 2000 -FallbackRuleNumberBegin 8000 
    
#>



Param (

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$RedirUrlPrefix,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = $PWD,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$HttpVserver,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$HttpsVserver,

    [int]$SpecificRuleNumberBegin = 1000,

    [int]$FallbackRuleNumberBegin = 9000,

    [int]$RuleNumberIncrement = 1,

    [int]$PriorityBegin = 100,

    [int]$PriorityIncrement = 10

)


# --------------------------------------------------
# Functions
# --------------------------------------------------

Function New-RedirectConfig {

    Param (

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RedirUrlPrefix,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RequestUrl,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$RedirectUrl,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$RuleNumber,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$Priority,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [string]$HttpVserver = $HttpVserver,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [string]$HttpsVserver = $HttpsVserver

    )


    # Fix-up
    $DomainFixup = $Domain
    $DomainCriteria = "(HTTP.REQ.HOSTNAME.SET_TEXT_MODE(IGNORECASE).EQ(\""$DomainFixup\""))"


    # --------------------------------------------------
    # Process request URL
    # --------------------------------------------------

    $RequestUrlEncoded = [System.Web.HttpUtility]::UrlEncode($RequestUrl).Replace('%2f', '/').Replace('%3f', '?')

    If ($RequestUrl -match "\*$") {

        # Request URL ends with a wildcard (*), so this will be a fall-back rule. Specfic rules will take precedence
        $RequestUrlFixup = "/$($RequestUrlEncoded.ToLower().TrimStart('/').TrimEnd('*'))"
        $RequestUrlCriteria = "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).STARTSWITH(\""$RequestUrlFixup\"")"

    }
    Else {

        # Fixup request URL - remove explicit leading and trailing slashes, explicitly prefix with a slash, thow-away query (after '?')
        $RequestUrlFixup = "/$($RequestUrlEncoded.ToLower().Trim('/'))"

        If ($RequestUrlFixup.Contains('?')) {
            $RequestUrlFixup = $RequestUrlFixup.Substring(0, $RequestUrlFixup.IndexOf('?'))
        }

        If ($RequestUrlFixup -eq '/') {

            # Requesting root of site (/)
            $RequestUrlCriteria = "HTTP.REQ.URL.EQ(\""/\"")"

        }
        Else {

            # Match requests for paths with or without trailing slash
            $RequestUrlCriteria = "HTTP.REQ.URL.PATH.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^$($RequestUrlFixup)/?$#)"

        }
    }

    $ResponderPolicyRequest = @($DomainCriteria, $RequestUrlCriteria) -join ' && '


    # --------------------------------------------------
    # Process redirect URL
    # --------------------------------------------------

    $RedirectUrlFixup = $RedirectUrl.TrimStart('/')

    $FullRedirectUrl = "$($RedirUrlPrefix.TrimEnd('/'))/$($RedirectUrlFixup)? + HTTP.REQ.URL.QUERY.HTTP_URL_SAFE"


    # --------------------------------------------------
    # Output NetScaler config lines
    # --------------------------------------------------

    @"
add responder action RespAct_$($RuleNumber.ToString("0000")) redirect "\"$FullRedirectUrl\"" -responseStatusCode 301
add responder policy RespPol_$($RuleNumber.ToString("0000")) "$ResponderPolicyRequest" RespAct_$($RuleNumber.ToString("0000"))
bind cs vserver $HttpVserver -policyName RespPol_$($RuleNumber.ToString("0000")) -priority $Priority -gotoPriorityExpression END -type REQUEST
bind cs vserver $HttpsVserver -policyName RespPol_$($RuleNumber.ToString("0000")) -priority $Priority -gotoPriorityExpression END -type REQUEST

"@

    $RequestUrlCriteria | ForEach-Object {
        # Write-Verbose """$_"" ==> $FullRedirectUrl" -Verbose
        Write-Host """$_"" ==> $FullRedirectUrl" -ForegroundColor DarkGray
    }

}

Function New-RollbackConfig {

    Param (

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$RuleNumber,

        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [int]$Priority,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [string]$HttpVserver = $HttpVserver,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [string]$HttpsVserver = $HttpsVserver,

        [switch]$UnbindOnly

    )



@"
unbind cs vserver $HttpVserver -policyName RespPol_$($RuleNumber.ToString("0000"))
unbind cs vserver $HttpsVserver -policyName RespPol_$($RuleNumber.ToString("0000"))

"@

    If (-Not($UnbindOnly)) {
@"
rm responder policy RespPol_$($RuleNumber.ToString("0000"))
rm responder action RespAct_$($RuleNumber.ToString("0000"))

"@
    }

}


Function Output-NetScalerCmd {

    Param (

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Rules

    )

    $WriterAppend = $false
    $WriterEncoding = New-Object System.Text.UTF8Encoding $False
    $writer = New-Object System.IO.StreamWriter $FileName, $WriterAppend, $WriterEncoding
    $writer.NewLine = "`n"

    $Rules -split "`r`n" | ForEach {
        If ($_.Length -gt 0) {
            $writer.WriteLine($_)
        }
    }

    $writer.Dispose()

}


# --------------------------------------------------
# Begin script
# --------------------------------------------------

Add-Type -AssemblyName System.Web


$RedirectCsv = Import-Csv -Path $CsvPath -Delimiter ';' | Sort-Object Domain, RequestUrl
Remove-Variable Rules -ErrorAction SilentlyContinue


# Specific redirects (separate rules for each redirect)
$RuleNumber = $SpecificRuleNumberBegin
$Priority = $PriorityBegin
$RedirectCsv | Where-Object {$_.RequestUrl -notmatch '\*'} | ForEach {

    $RedirectCmd += New-RedirectConfig -Domain $_.Domain -RedirUrlPrefix $RedirUrlPrefix -RequestUrl $_.RequestUrl -RedirectUrl $_.RedirectUrl -RuleNumber $RuleNumber -Priority $Priority
    $UnbindCmd += New-RollbackConfig -RuleNumber $RuleNumber -Priority $Priority -UnbindOnly
    $RollBackCmd += New-RollbackConfig -RuleNumber $RuleNumber -Priority $Priority

    $RuleNumber = $RuleNumber + $RuleNumberIncrement
    $Priority = $Priority + $PriorityIncrement

}


# Fallback redirects (separate rules for each redirect)
$RuleNumber = $FallbackRuleNumberBegin
$RedirectCsv | Where-Object {$_.RequestUrl -match '\*'} | ForEach {

    $RedirectCmd += New-RedirectConfig -Domain $_.Domain -RedirUrlPrefix $RedirUrlPrefix -RequestUrl $_.RequestUrl -RedirectUrl $_.RedirectUrl -RuleNumber $RuleNumber -Priority $Priority
    $UnbindCmd += New-RollbackConfig -RuleNumber $RuleNumber -Priority $Priority -UnbindOnly
    $RollBackCmd += New-RollbackConfig -RuleNumber $RuleNumber -Priority $Priority

    $RuleNumber = $RuleNumber + $RuleNumberIncrement
    $Priority = $Priority + $PriorityIncrement

}


# Output to batch file (UTF8, LF EOL)
If (Test-Path -Path $OutputPath) {

    $TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"


    # --------------------------------------------------
    # Duplicate input file
    # --------------------------------------------------
    
    $OutputInput = "$OutputPath\$($TimeStamp)_input.csv"
    Copy-Item -Path $CsvPath -Destination $OutputInput


    # --------------------------------------------------
    # Redirects
    # --------------------------------------------------
    
    $OutputRedirects = "$OutputPath\$($TimeStamp)_redirects.txt"
    Output-NetScalerCmd -FileName $OutputRedirects -Rules $RedirectCmd


    # --------------------------------------------------
    # Unbind
    # --------------------------------------------------

    # Syntax: unbind cs vserver CSW_VIP_HTTPS-Redirects -policyName RespPol_9000 -type REQUEST -priority 140
    $OutputUnbind = "$OutputPath\$($TimeStamp)_unbind.txt"
    Output-NetScalerCmd -FileName $OutputUnbind -Rules $UnbindCmd


    # --------------------------------------------------
    # Rollback
    # --------------------------------------------------

    $OutputRollback = "$OutputPath\$($TimeStamp)_rollback.txt"
    Output-NetScalerCmd -FileName $OutputRollback -Rules $RollBackCmd


    # --------------------------------------------------
    # Print result
    # --------------------------------------------------

    Write-Host "NetScaler batch configuration ($($RedirectCsv.Count) rules):" -ForegroundColor White
    Write-Host "  Input:         $OutputInput" -ForegroundColor Cyan
    Write-Host "  Redirects:     $OutputRedirects" -ForegroundColor Green
    Write-Host "  Unbind:        $OutputUnbind" -ForegroundColor Yellow
    Write-Host "  Rollback:      $OutputRollback" -ForegroundColor Red

}
Else {

    Throw "Output path ""$OutputPath"" not found. No files generated."

}