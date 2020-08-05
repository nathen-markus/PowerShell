$MainGroup = "SQL-VS8PMISC.Misc.RO"

$nestedGroups = Get-ADGroupMember -Server "qbeai.com" -Identity $MainGroup | Where-Object {$_.objectClass -eq "group"}

foreach ($group in $nestedGroups.Name)
{
    Write-Output "Removing $group from $MainGroup"
    Remove-ADGroupMember -Server "qbeai.com" -Identity $MainGroup -Members $group -Confirm:$false

    $allNestedMembers = Get-ADGroupMember -Server "qbeai.com" -Identity $group -Recursive | Where-Object {$_.objectClass -eq "user"}

    if($allNestedMembers -eq $null)
    {
        Write-Output "No members to add from $group"
    }
    else {
        Write-Output "Adding members directly into $MainGroup : `n $($allNestedMembers.Name)"
        Add-ADGroupMember -Server "qbeai.com" -Identity $MainGroup -Members $allNestedMembers -Confirm:$false
    }

}