$date = Get-Date -UFormat "%m-%Y"
Get-ADUser -Service yourdomain -SearchBase OU=YourUserAccountOU -Properties name,samaccountname,description,manager,whencreated,LastLogonTimestamp,LastLogon,employeeID | select name,samaccountname,description,manager,whencreated,LastLogonTimestamp,LastLogon,employeeID | where {$_.LastLogonTimeStamp -le (Get-date).AddDays(-94)} | Export-Csv "\\ReportLocation\Report-90 Day Inactivity-$date.csv" -Append -NoTypeInformation -Force

