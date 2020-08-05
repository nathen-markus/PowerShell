$inactives = Import-Csv "\\YourReportLocation\ForDisable.csv"

foreach ($inactive in $inactives)

{
    $Domain = YourDomain.com
    ##verifies the correct AD object is being targeted
    $object = Get-ADUser -Server $Domain -Identity $inactive.samaccountname -Properties * 
    ##grabs the date for the logs
    $date = Get-Date -UFormat "%m-%d-%Y"
    ##sets a note in the telephone notes field why the account was disabled
    $notes = "DISABLED: Inactive 90 days"
    ##creates the log file
    "$($object.SamAccountName),$date,`"$($object.Description)`",$($object.DistinguishedName)" | Out-File -Encoding ascii -FilePath "\\YourReportLocation\Log-90 Day Inactivity-$date.csv" -Append

    ##sets notes
    Set-ADObject -Server $Domain -Identity $object.DistinguishedName -Replace @{info=$notes}
    ##disables the account
    Disable-ADAccount -Identity $object.DistinguishedName -Server $Domain
    ##moves the account to your inactive OU for clean up
    Move-ADObject -Identity $object.DistinguishedName -TargetPath OU=YourInactiveOU -Server $Domain
    

    }