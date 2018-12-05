# NetScaler-GenerateRedirects

## Synopsis

Generates a NetScaler batch configuration file, for configuring redirects based on a list of redirect rules.

Request URLs containing wilcards ("*") are considered fallback redirect rules, and will be the last rules to be added.

## Input

### Redirects Csv File

Requirements:

- Headers must be: "Domain", "RequestUrl", "RedirectUrl"
- Fields must be semicolon-separated (the `Import-Csv` command)
- The file format must be in UTF8 (Excel: Save as "CSV UTF-8")
- No blank lines (could probably easily be ignored in a future version)
- RequestUrls are automatically URL encoded - otherwise the NetScaler rules may not work

### Parameters

Mandatory parameters are:

| Parameter name | Description |
| --- | --- |
| RedirUrlPrefix | The text string to prefix the redirected URLs with, e.g. "https://www.newdomain.tld" |
| HttpVserver | The name of the content switch virtual server for HTTP requests |
| HttpsVserver | The name of the content switch virtual server for HTTPS requests |

## Output

### Redirects Batch File

Example (using "Redirects_Example.csv"):

```
add responder action RespAct_1000 redirect "\"https://www.newdomain.tld/brand/new/path/\"" -responseStatusCode 301
add responder policy RespPol_1000 "(HTTP.REQ.HOSTNAME.SET_TEXT_MODE(IGNORECASE).EQ(\"otherdomain.tld\")) && HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/?$#)" RespAct_1000
bind cs vserver CSW_VIP_HTTP-Redirects -policyName RespPol_1000 -priority 100 -gotoPriorityExpression END -type REQUEST
bind cs vserver CSW_VIP_HTTPS-Redirects -policyName RespPol_1000 -priority 100 -gotoPriorityExpression END -type REQUEST
...

```

### Unbind Batch File

TBD. A batch file to unbind the policies that the "Redirects" batch file creates.

### Rollback Batch File

TBD. A batch file to unbind the policies, and delete responder policies and actions.

## Example Usage

To run the script with the fewest possible parameters:

```PowerShell
.\NetScaler-GenerateRedirects.ps1 -CsvPath .\Redirects_Example.csv -RedirUrlPrefix "https://www.newdomain.tld/" -HttpVserver CSW_VIP_HTTP-Redirects -HttpsVserver CSW_VIP_HTTPS-Redirects
```

Example output (using "Redirects_Example.csv"):

```
"HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/?$#)" ==> https://www.newdomain.tld/brand/new/path/
"HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/sub-path/?$#)" ==> https://www.newdomain.tld/brand/new/path/
"HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).REGEX_MATCH(re#^/another-old-path/sub-path/old-page/?$#)" ==> https://www.newdomain.tld/brand/new/path/new-page
"HTTP.REQ.URL.EQ(\"/\")" ==> https://www.newdomain.tld/new/path/
"HTTP.REQ.URL.SET_TEXT_MODE(IGNORECASE).STARTSWITH(\"/some-old-path/\")" ==> https://www.newdomain.tld/brand/new/path/
NetScaler batch configuration outputs (5 rules):
  Redirects:     C:\code\private\NetScaler-GenerateRedirects\20181205-145528_redirects.txt
```

For detailed information: `Get-Help .\NetScaler-GenerateRedirects.ps1`

## References

- https://docs.citrix.com/en-us/netscaler/12/appexpert/policies-and-expressions/ns-regex-wrapper-con/ns-regex-basic-charactrstcs-con.html
- https://docs.citrix.com/en-us/netscaler/12/appexpert/policies-and-expressions/ns-regex-wrapper-con/ns-regex-operations-con.html
- https://docs.citrix.com/en-us/netscaler/12/appexpert/policies-and-expressions/ns-pi-Adv-exp-eval-txt-wrapper-con/ns-pi-basic-operations-con.html
- https://docs.citrix.com/en-us/netscaler/12/appexpert/responder/responder-action-policy-examples.html