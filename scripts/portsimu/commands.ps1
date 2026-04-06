 # 1) Put names in a file (one per line), e.g. apps.txt:
Get-ExecutionPolicy
# myapi.azurewebsites.net
cd \Users\vmuser\Documents
# 2) Run the script:
.\privdnstest.ps1 -InputFile .\dnsnames.txt -Types A,CNAME -DnsServer 10.6.1.115 
-OutCsv .\dns-results.csv

# Or pass them directly:
$apps = 'web1','web2','myapi.azurewebsites.net'
.\Test-AzureWebsitesDns.ps1 -Names $apps -Types A,AAAA,CNAME

Resolve-DnsName ncus-app-prd-appsvc-engagementapi.azurewebsites.net -Server 172.17.110.101 
