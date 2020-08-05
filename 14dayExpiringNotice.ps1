# ---------------- 
# Define variables 
# ---------------- 
 
$To = "QBE-Security.US-BOX@us.qbe.com" 
$From = "QBE-Security.US-BOX@us.qbe.com" 
$Subject = "Non-Employee Expiration Date(s) - Report" 
$Body = "The attached CSV file contains a list of user accounts in the QBEAI domain that are due to expire in the next 14 days." 
$SMTPServer = "qbe-smtp.qbeai.com" 
$Date = Get-Date -format yyyyMMdd 
$ReportName = "\\qbeai.com\depts\Technology\Security\Security Administration\Reporting\Contractors\ContractorReport_$((Get-Date).ToString('MM-dd-yyyy')).csv" 
 
 
 
# ------------------------------------------------------------------ 
# Get list of users from Active Directory that will expire in 14 days 
# ------------------------------------------------------------------ 
 
$UserList = Search-ADAccount -AccountExpiring -UsersOnly -TimeSpan 14.00:00:00 | Sort-Object -Descending AccountExpirationDate 
 
 
 
# ----------------------------------------------- 
# Send an email using the variables defined above 
# ----------------------------------------------- 
 
If ($UserList -eq $null){} 
Else 
{ 
   $UserList | Export-CSV $ReportName -NoTypeInformation
   Send-MailMessage -To $To -From $From -Subject $Subject -Body $Body -SMTPServer $SMTPServer -Attachments $ReportName 
} 