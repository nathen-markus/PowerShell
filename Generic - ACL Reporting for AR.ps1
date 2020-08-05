###############################################################################
# FILENAME: ACLReporting-AR.ps1
# VERSION:  0.1
# AUTHOR:   Nathen Markus
# UPDATES:  
#   10/24/2017: * (v0.1)
#                   - Initial development.
#
# DESCRIPTION:
#   Script builds Access Recertification Reports for the certification of 
#   ACL grants against directories, including access and nested group members,
#   for applications that have manual review components.
#
# TODO: N/A
#
###############################################################################

# Start console logging
Start-Transcript -Path ".\AR-build-acl-report-w-nested-groups-CONSOLE-LOG.txt"

# Set up logging. Log and notify console of script start. Log initialization start.
$StartTime = Get-Date -format 'u'
Write-Host "$StartTime - START: AR-build-ad-group-membership-report.ps1 script starting."
Write-Host "$(Get-Date -format 'u') - INFO: Begin script initialization."

# Initialize array for groups requiring enumeration
$GroupList = New-Object System.Collections.ArrayList

# Initialize array for ACL report line items
$ACLReportOutput = New-Object System.Collections.ArrayList
$ACLReportOutput.Add("Approve,Revoke,Location,Rights,Access Control Type,Inherited,Identity,Identity Type,First Name,Last Name,User Manager Name / Group Notes") > $null
$ACLReportOutputFileName = ".\AR-ACL-identity-report.csv"

# Initialize array for group membership report line items
$GroupReportOutput = New-Object System.Collections.ArrayList
$GroupReportOutput.Add("Approve,Revoke,Group Name,Domain,User ID,First Name,Last Name,Manager Name") > $null
$GroupReportOutputFileName = ".\AR-ACL-group-report.csv"

# Initialize assorted counters
$LocationCount = 0
$LocationIndex = 0

# Read the list of locations to process (text file, one location per line) and notify console of results.
Write-Host "$(Get-Date -format 'u') - INFO: Loading locations to process..."
$Locations = Import-Csv -Path ".\AR-AD-ACLs.csv"
$LocationCount = $Locations.Path.Count
Write-Host "$(Get-Date -format 'u') - INFO: ...$LocationCount locations loaded."

#########################
# LOCATION LOOP - START #
#########################

Write-Host "$(Get-Date -format 'u') - INFO: Begin processing $LocationCount locations."

# FOREACH location in the location array do the following:
ForEach($Location in $Locations){
    # Bump location index counter, initialize assorted ephemeral counters, and notify console of start.
    $LocationIndex++
    $IdentityIndex = 0
    Write-Host "$(Get-Date -format 'u') - INFO: Processing location $LocationIndex of $LocationCount`: $($Location.Path)."

    # Get the ACL on the location item, assign it to variable for use, notify console of high-level details.
    $ACL = Get-Acl -Path $Location.Path
    Write-Host "$(Get-Date -format 'u') - INFO: Location owner: $($ACL.Owner)"
    Write-Host "$(Get-Date -format 'u') - INFO: Location total access grants: $($ACL.Access.Count)"
    
    # FOREACH ACL item do the following:
    $ACL.Access.ForEach({
        # Bump identity index
        $IdentityIndex++
        
        # Get and set various attributes about the grant and notify console of processing ACL item
        $IdentityReference = $_.IdentityReference.ToString().Split("\")
        
        If($IdentityReference[0].StartsWith("S-1-")) {  # IF orphaned SID, set type as such
            $IdentityDomain = $Location.Domain
            $IdentitySAM = $IdentityReference[0]
        } Else {                                        # ELSE set type from object
            $IdentityDomain = $IdentityReference[0]
            $IdentitySAM = $IdentityReference[1]
        }
        
        $Type = $_.AccessControlType
        $Rights = $_.FileSystemRights
        $Inherited = $_.IsInherited
        
        Write-Host "$(Get-Date -format 'u') - INFO: Processing identity $IdentityIndex of $($ACL.Access.Count): $IdentitySAM"

        # Check identity class (user / group) and act acordingly:
        $IdentityObject = Get-QADObject -Service $IdentityDomain -Identity $IdentitySAM

        # IF identity is a group, check group list to see if already present, IF not add group to group list. Then look up group, add report line item formatted for that type
        # ELSEIF identity is a user, look up user, add report line item formatted for that type
        # ELSE add report line item as type orphaned SID and REPORT WARNING FOR ANALYST FOLLOW-UP
        If($($IdentityObject.Type) -eq "group"){
            $GroupAlreadyExists = 0                                                         # Initialize quick counter
            $GroupList.ForEach({                                                            # FOR EACH group in the list
                If($_[1] -eq $IdentitySAM){                                              # IF list item matches group
                    $GroupAlreadyExists++                                                   #   - bump counter and report out
                    Write-Host "$(Get-Date -format 'u') - INFO: $IdentitySAM is object type group - already present in group list for processing"
                }
            })
            If($GroupAlreadyExists -eq 0){                                                  # IF the counter was not touched
                $GroupList.Add(@($IdentityDomain,$IdentitySAM)) > $null               # - add group to the list and report out
                Write-Host "$(Get-Date -format 'u') - INFO: $IdentitySAM is object type group - added to group list for processing"
            }
            $Group = Get-QADGroup -Service $IdentityDomain -SamAccountName $IdentitySAM -IncludedProperties 'notes'
            $ACLReportOutput.Add(",,$($Location.Path),`"$Rights`",$Type,$Inherited,$IdentitySAM,$($IdentityObject.Type),***GROUP***,***MEMBERSHIP***,`"$($Group.notes)`"") > $null
        } ElseIf ($($IdentityObject.Type) -eq "user"){
            $User = Get-QADUser -Service $IdentityDomain -Identity $IdentitySAM -IncludedProperties 'SamAccountName','GivenName','sn','extensionAttribute1'
            $ACLReportOutput.Add(",,$($Location.Path),`"$Rights`",$Type,$Inherited,$IdentitySAM,$($IdentityObject.Type),$($User.GivenName),$($User.sn),`"$($User.extensionAttribute1)`"") > $null
        } Else {
            $ACLReportOutput.Add(",,$($Location.Path),`"$Rights`",$Type,$Inherited,$IdentitySAM,$($IdentityObject.Type),WARNING,ORPHANED,SID") > $null
            Write-Host "$(Get-Date -format 'u') - WARNING: $IdentitySAM is an unknown / orphaned object."
        }
    })
}

# Notify console location loop complete
Write-Host "$(Get-Date -format 'u') - INFO: Completed processing $LocationCount locations."

#######################
# LOCATION LOOP - END #
#######################

######################
# GROUP LOOP - START #
######################

# Initialize assorted counters and notify console of start
$GroupIndex = 0                 # Group Loop index counter
$GroupCount = $GroupList.Count  # Initial setting of number of groups...start with count pulled from the location ACLs themselves
Write-Host "$(Get-Date -format 'u') - INFO: Begin processing $GroupCount groups."

# WHILE the number of groups in group array is greater than the index do the following
#   - NOTE: I implemented loop this way because of possibility new groups will be added during each loop cycle, which breaks a ForEach
While($GroupList.Count -gt $GroupIndex){
    
    # Bump group index counter, set values from $GroupList array item for processing and notify console
    $GroupDomain = $GroupList[$GroupIndex][0]       # set group domain
    $GroupName = $GroupList[$GroupIndex][1]         # set group name
    $GroupIndex++                                   # bump index
    Write-Host "$(Get-Date -format 'u') - INFO: Processing group $GroupIndex of $GroupCount`: $GroupName"

    $GroupMembers = Get-QADGroupMember -Service $GroupDomain -Identity $GroupName -IncludedProperties SamAccountName -Indirect -KeepForeignSecurityPrincipals
    $GroupMembersCount = $GroupMembers.Count

    #############################
    # GROUP MEMBER LOOP - START #
    #############################

    # IF the group isn't empty, loop through the GroupMembers for reporting.
    # ELSE report that group is empty and move on.
    if($GroupMembersCount -gt 0) {
        
        # Initialize counter and notify console of start
        $MemberIndex = 0        # User Loop index counter
        Write-Host "$(Get-Date -format 'u') - INFO: Enumerating member data for $GroupMembersCount group members."
        
        # FOREACH group member do the following...
        $GroupMembers.ForEach({

            # Initialize assorted values and notify console of start
            $MemberIndex++                                                  # Bump index
            $GroupMember = $_                                               # Copy array member as working object
            $GroupMemberDomain = $GroupMember.NTAccountName.Split('\')[0]   # Set domain
            $GroupMemberDN = $GroupMember.DN.Split(',')                     # Set DN
            $GroupMemberSAM = $GroupMember.SamAccountName                   # Set SamAccountName
            Write-Host "$(Get-Date -format 'u') - INFO: Querying member $MemberIndex of $GroupMembersCount`: $GroupMemberSAM"
            
            # Build report line item.
            # IF array item is type group, report it out and move on
            # ELSEIF array item is type foreignsecurityprincipal, report it out and move on
            # ELSE check the group's domain for the user and do the following:
            #   - IF object returned, report on it and move on
            #   - ELSEIF check qbeai.com, rt.win-na.com, and gc.win-na.com through the big if-else plinko board, report out and move on
            #   - ELSE report out that the user cannot be looked up and move on
            if ($GroupMember) {                                                                     # IF we have a group do the following:
                if($GroupMember.Type -match 'group') {                                              # IF item is type group
                    $GroupAlreadyExists = 0                                                         # Initialize quick counter
                    $GroupList.ForEach({                                                            # FOR EACH group in the list
                        If($_[1] -eq $GroupMemberSAM){                                              # IF list item matches group
                            $GroupAlreadyExists++                                                   #   - bump counter and report out
                            Write-Host "$(Get-Date -format 'u') - INFO: $GroupMemberSAM is object type group - already present in group list for processing, moving on"
                        }
                    })
                    If($GroupAlreadyExists -eq 0){                                                  # IF the counter was not touched
                        $GroupList.Add(@($GroupMemberDomain,$GroupMemberSAM)) > $null               # - add group to the list and report out
                        Write-Host "$(Get-Date -format 'u') - INFO: $GroupMemberSAM is object type group - added to group list for further processing"
                    }
                } elseif ($GroupMember.Type -match 'foreignSecurityPrincipal') {                    # ELSEIF item is type foreignSecurityPrincipal, add report line item formatted for that type
                    $UserResult = (",," + $GroupName + "," + $GroupMemberDomain + "," + $GroupMemberDN + "," + "," + "," + ",")
                    $GroupReportOutput.Add($UserResult) > $null
                    Write-Host "$(Get-Date -format 'u') - WARN: $GroupMemberSAM ($($GroupMember.Type)) added to report"
                } else {                                                                            # ELSE process item as user
                    $UserQuery = Get-QADUser -Service $GroupMemberDomain -Identity $GroupMemberSAM -IncludedProperties 'SamAccountName','GivenName','sn','extensionAttribute1'
                    if($UserQuery) {                                                                # IF group domain matches user domain, look up user as such, add report line item formatted for that type
                        $UserResult = (",," + $GroupName + "," + $GroupMemberDomain + "," + $UserQuery.SamAccountName + "," + $UserQuery.GivenName + "," + $UserQuery.sn  + "," + $UserQuery.extensionAttribute1)
                        $GroupReportOutput.Add($UserResult) > $null
                        Write-Host "$(Get-Date -format 'u') - INFO: $GroupMemberSAM ($($UserQuery.GivenName) $($UserQuery.sn)) added to report"
                    } else {                                                                        # ELSE look up user by stepping through through THE GREAT PLINKO BOARD OF QUEST LOOKUPS(TM)!!!
                        $UserQuery = Get-QADUser -Service qbeai.com -Identity $GroupMemberSAM -IncludedProperties 'SamAccountName','GivenName','sn','extensionAttribute1'
                        if($UserQuery) {                                                            # IF user is in qbeai.com, look up user as such, add report line item formatted for that type
                            $UserResult = (",," + $GroupName + "," + "qbeai.com" + "," + $UserQuery.SamAccountName + "," + $UserQuery.GivenName + "," + $UserQuery.sn  + "," + $UserQuery.extensionAttribute1)
                            $GroupReportOutput.Add($UserResult) > $null
                            Write-Host "$(Get-Date -format 'u') - INFO: $GroupMemberSAM ($($UserQuery.GivenName) $($UserQuery.sn) added to report"
                        } else {                                                                    # ELSE, look elsewhere
                            $UserQuery = Get-QADUser -Service rt.win-na.com -Identity $GroupMemberSAM -IncludedProperties 'SamAccountName','GivenName','sn','extensionAttribute1'
                            if($UserQuery) {                                                        # IF user is in rt.win-na.com, look up user as such, add report line item formatted for that type
                                $UserResult = (",," + $GroupName + "," + "rt.win-na.com" + "," + $UserQuery.SamAccountName + "," + $UserQuery.GivenName + "," + $UserQuery.sn  + "," + $UserQuery.extensionAttribute1)
                                $GroupReportOutput.Add($UserResult) > $null
                                Write-Host "$(Get-Date -format 'u') - INFO: $GroupMemberSAM ($($UserQuery.GivenName) $($UserQuery.sn)) added to report"
                            } else {                                                                # ELSE, look elsewhere
                                $UserQuery = Get-QADUser -Service gc.win-na.com -Identity $GroupMemberSAM -IncludedProperties 'SamAccountName','GivenName','sn','extensionAttribute1'
                                if($UserQuery) {                                                    # IF user is in gc.win-na.com, look up user as such, add report line item formatted for that type
                                    $UserResult = (",," + $GroupName + "," + "gc.win-na.com" + "," + $UserQuery.SamAccountName + "," + $UserQuery.GivenName + "," + $UserQuery.sn  + "," + $UserQuery.extensionAttribute1)
                                    $GroupReportOutput.Add($UserResult) > $null
                                    Write-Host "$(Get-Date -format 'u') - INFO: $GroupMemberSAM ($($UserQuery.GivenName) $($UserQuery.sn)) added to report"
                                } else {                                                            # ELSE, user is unknown to our Quest-managed domains, add report line item with what we know and move on
                                    $UserResult = (",," + $GroupName + "," + $GroupMemberDomain + "," + $GroupMemberSAM + "," + "" + "," + ""  + "," + "")
                                    $GroupReportOutput.Add($UserResult) > $null
                                    Write-Host "$(Get-Date -format 'u') - WARN: $GroupMemberSAM (UNKNOWN) added to report"
                                }
                            }
                        }
                    }
                }
            } else {                                                                                # ELSE, report out that the item does not exist in the places we know to look
                $UserResult = (",," + $GroupName + "," + $GroupMemberDomain + "," + $GroupMemberDN + "ERROR," + "DOES," + "NOT," + "EXIST,")
                $GroupReportOutput.Add($UserResult) > $null
                Write-Host "$(Get-Date -format 'u') - WARN: $GroupMemberSAM (UNKNOWN) added to report"
            }
        })
        
        # Notify console of results of user loop processing.
        Write-Host "$(Get-Date -format 'u') - INFO: Retrieved $MemberIndex group members. $($GroupList.Count - $GroupCount) new groups added for processing."
        Write-Host "$(Get-Date -format 'u') - INFO: End group processing $GroupIndex of $GroupCount`: $GroupName"
        
        # Update counter with current list of groups for next go 'round
        $GroupCount = $GroupList.Count

    } else {
        # Report empty group and notify console
        $UserResult = (",," + $GroupName + "," + $GroupMemberDomain + "," + "WARNING," + "IS," + "AN," + "EMPTY," + "GROUP,")
        Write-Host "$(Get-Date -format 'u') - WARN: Group $GroupIndex of $GroupCount`: $GroupName has no members!"
    }
    
    ###########################
    # GROUP MEMBER LOOP - END #
    ###########################

    # Remove $GroupMembers array out of an abundance of caution
    Remove-Item Variable:GroupMembers
}

# Notify console group loop complete
Write-Host "$(Get-Date -format 'u') - INFO: Finished processing $GroupCount total groups."

####################
# GROUP LOOP - END #
####################

#####################
# REPORTING - START #
#####################

# Write reports to files and notify console
$ACLReportOutput | Out-File -Encoding ascii -FilePath $ACLReportOutputFileName
Write-Host "$(Get-Date -format 'u') - INFO: ACL report written to file: $ACLReportOutputFileName"
$GroupReportOutput | Out-File -Encoding ascii -FilePath $GroupReportOutputFileName
Write-Host "$(Get-Date -format 'u') - INFO: Group report written to file: $GroupReportOutputFileName"

# Notify console of script completion
$StopTime = Get-Date -format 'u'
Write-Host "$StopTime - END: AR-build-acl-report-w-nested-groups.ps1 script complete. Total run time: $((New-TimeSpan -Start $StartTime -End $StopTime).TotalSeconds) seconds"

###################
# REPORTING - END #
###################

# Stop transcript
Stop-Transcript