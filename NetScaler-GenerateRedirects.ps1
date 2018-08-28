<#

- Save in "CSV UTF-8" format, semicolon separated
- No blank lines
- Headers: "Domain", "RequestUrl", "RedirectUrl"
- RequestURLs are automatically URL encoded - otherwise the NetScaler rules may not work

https://docs.citrix.com/en-us/netscaler/11/appexpert/policies-and-expressions/ns-regex-wrapper-con/ns-regex-basic-charactrstcs-con.html
https://docs.citrix.com/en-us/netscaler/11/appexpert/policies-and-expressions/ns-regex-wrapper-con/ns-regex-operations-con.html
https://docs.citrix.com/zh-cn/netscaler/11/appexpert/policies-and-expressions/ns-pi-Adv-exp-eval-txt-wrapper-con/ns-pi-basic-operations-con.html

#>

Param (

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = $PWD,

    [Parameter(Mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [string]$HttpVserver = $global:HttpVserver,

    [Parameter(Mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [string]$HttpsVserver = $global:HttpsVserver,

    [ValidateNotNullOrEmpty()]
    [string]$global:RedirUrlPrefix = 'https://www.newdomain.tld/',

    [int]$SpecificRuleNumberBegin = 1000,

    [int]$FallbackRuleNumberBegin = 9000,

    [int]$RuleNumberIncrement = 1,

    [int]$PriorityBegin = 100,

    [int]$PriorityIncrement = 10

)



Function New-RedirectConfig {

    Param (

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$RequestUrl,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$RedirectUrl,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [int]$RuleNumber,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [int]$Priority,

        [Parameter(Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [string]$HttpVserver = $global:HttpVserver,

        [Parameter(Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [string]$HttpsVserver = $global:HttpsVserver

    )


    # Fix-up
    $DomainFixup = $Domain
    $DomainCriteria = "(HTTP.REQ.HOSTNAME.SET_TEXT_MODE(IGNORECASE).EQ(\""$DomainFixup\""))"

    $RedirectUrlFixup = $RedirectUrl.TrimStart('/')
    $FullRedirectUrl = "$($global:RedirUrlPrefix.TrimEnd('/'))/$RedirectUrlFixup"

    $RequestUrlEncoded = [System.Web.HttpUtility]::UrlEncode($RequestUrl).Replace('%2f','/')

    # Build strings for config

    If ($RequestUrl -match "\*") {
        $RequestUrlFixup = "/$($RequestUrlEncoded.ToLower().TrimStart('/').TrimEnd('*'))"
        $RequestUrlCriteria = "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).STARTSWITH(\""$RequestUrlFixup\"")"
    } Else {
        $RequestUrlFixup = "/$($RequestUrlEncoded.ToLower().Trim('/'))"
        If ($RequestUrlFixup -eq '/') {
            $RequestUrlCriteria = "HTTP.REQ.URL.EQ(\""$RequestUrlFixup\"")"
        } Else {
            $RequestUrlCriteria = "HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^$RequestUrlFixup/?$#)"
        }
    }

    $ResponderPolicyRequest = @($DomainCriteria, $RequestUrlCriteria) -join ' && '

@"
add responder action RespAct_$($RuleNumber.ToString("0000")) redirect "\"$FullRedirectUrl\"" -responseStatusCode 301
add responder policy RespPol_$($RuleNumber.ToString("0000")) "$ResponderPolicyRequest" RespAct_$($RuleNumber.ToString("0000"))
bind cs vserver $HttpVserver -policyName RespPol_$($RuleNumber.ToString("0000")) -priority $Priority -gotoPriorityExpression END -type REQUEST
bind cs vserver $HttpsVserver -policyName RespPol_$($RuleNumber.ToString("0000")) -priority $Priority -gotoPriorityExpression END -type REQUEST

"@

    $RequestUrlCriteria | ForEach {
        Write-Verbose """$_"" ==> $FullRedirectUrl" -Verbose
    }

}


If (Test-Path -Path $OutputFile) {
    $OutputTofile = $false
} Else {
    $OutputTofile = $true
}


$RedirectCsv = Import-Csv -Path $CsvPath -Delimiter ';' | Sort-Object Domain, RequestUrl
Remove-Variable Rules -ErrorAction SilentlyContinue


# Specific redirects (separate rules for each redirect)
$RuleNumber = $SpecificRuleNumberBegin
$Priority = 100
$RedirectCsv | Where-Object {$_.RequestUrl -notmatch '\*'} | ForEach {

    $Rules += New-RedirectConfig -Domain $_.Domain -RequestUrl $_.RequestUrl -RedirectUrl $_.RedirectUrl -RuleNumber $RuleNumber -Priority $Priority

    $RuleNumber = $RuleNumber + $RuleNumberIncrement
    $Priority = $Priority + $PriorityIncrement

}


# Fallback redirects (separate rules for each redirect)
$RuleNumber = $FallbackRuleNumberBegin
$RedirectCsv | Where-Object {$_.RequestUrl -match '\*'} | ForEach {

    $Rules += New-RedirectConfig -Domain $_.Domain -RequestUrl $_.RequestUrl -RedirectUrl $_.RedirectUrl -RuleNumber $RuleNumber -Priority $Priority

    $RuleNumber = $RuleNumber + $RuleNumberIncrement
    $Priority = $Priority + $PriorityIncrement

}

$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutputFile = "$OutputPath\redirects_$TimeStamp.txt"
$WriterAppend = $false
$WriterEncoding = New-Object System.Text.UTF8Encoding $False
$writer = New-Object System.IO.StreamWriter $OutputFile, $WriterAppend, $WriterEncoding
$writer.NewLine = "`n"

$Rules -split "`r`n" | ForEach {
    If ($_.Length -gt 0) {
        $writer.WriteLine($_)
    }
}

$writer.Dispose()