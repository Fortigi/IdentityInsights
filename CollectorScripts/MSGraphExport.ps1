#################################################################################################################
# Start
#################################################################################################################

Import-Module FortigiGraph -MinimumVersion 1.0.20240206.1453

#File Prefix
$FilePrefix = "MSGraph"

#Set Temp Date Folder
$DataFolder = ($env:TEMP + "\" + $FilePrefix + ".Export")

#Test Data Folder Path and create export folder
If (!(Test-Path -Path $DataFolder)) {
    New-Item -Path $DataFolder -ItemType Directory
}

$TranscriptFileName = ($FilePrefix + ".Export.Transcript_" + (Get-Date -format yyyy-MM-dd-HHmm) + ".txt")
Start-Transcript -Path ($env:TEMP + "\" + $TranscriptFileName) -Force

#Set the export date and time in a JSON
$DateFile = @{
    "Date" = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
} 
$DateFile | ConvertTo-Json | Out-File ($DataFolder + "\" + $FilePrefix + ".DateFile.Json") -Force

#################################################################################################################
# Script
#################################################################################################################

#Connect to Graph if not yet connected
$TenantName = Get-AutomationVariable -Name TenantName
$TenantName = Get-AutomationVariable -Name TenantName
$ClientID = Get-AutomationVariable -Name MSGraph-ClientID
$ClientSecret = Get-AutomationVariable -Name MSGraph-ClientSecret
Get-FGAccessToken -TenantId $TenantName -ClientId $ClientID -ClientSecret $ClientSecret

#Specify the ms Graph URL to use
$GraphURI = 'https://graph.microsoft.com/beta'

#Export basic tenant Info
$URI = $GraphURI + '/organization'
$File = ($DataFolder + "\" + $FilePrefix + ".Org.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export Users
$URI = $GraphURI + '/users?$expand=extensions'
$File = ($DataFolder + "\" + $FilePrefix + ".Users.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export User SignInActivity
$URI = $GraphURI + '/users?$select=displayName,signInActivity'
$File = ($DataFolder + "\" + $FilePrefix + ".UserSignIns.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export UserManagers
$URI = $GraphURI + '/users?$expand=manager($select=id)&$select=id'
$File = ($DataFolder + "\" + $FilePrefix + ".UserManagers.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export Groups
$URI = $GraphURI + '/groups'
$File = ($DataFolder + "\" + $FilePrefix + ".Groups.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Get Groups
$URI = $GraphURI + '/groups?$select=id,isAssignableToRole,groupTypes'
[array]$Groups = Invoke-FGGetRequest -URI $URI

#Export Group Memberships
[array]$GroupMembership = $null
$File = ($DataFolder + "\" + $FilePrefix + ".GroupMembership.Json")
Foreach ($Group in $Groups) {

    $URI = $GraphURI + "/groups/" + $Group.id + '/members?$select=id'
    Write-Output $URI
    [array]$Members = Invoke-FGGetRequest -URI $URI

    Foreach ($Member in $Members) {
        $Row = @{
            "groupId"    = $Group.id
            "memberId"   = $Member.id
            "memberType" = $Member.'@odata.type'
        }
        $GroupMembership += $Row
    }
    
}
$GroupMembership | ConvertTo-Json -Depth 10 | Out-File $File -Force

#Export GroupOwners
$URI = $GraphURI + '/groups?$expand=owners($select=id)&$select=id'
$File = ($DataFolder + "\" + $FilePrefix + ".GroupOwners.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export Eligible Group Members
[array]$GroupEligibleMembers = $null
$File = ($DataFolder+"\"+$FilePrefix+".GroupEligibleMembers.Json")

#This is no way to do this with one qeury we need to do it group by group or user by user.
#Filter Groups that can't used in PIM
$PIMGroups = $Groups | Where-Object { $_.groupTypes -notcontains "DynamicMembership" }
Foreach ($Group in $PIMGroups) {
    $URI = $GraphURI + "/identityGovernance/privilegedAccess/group/eligibilitySchedules?" + '$filter' + "=groupId eq '" + $group.id + "'"
    Try {
        Write-Output $URI
        $Result = Invoke-FGGetRequest -Uri $URI
        Write-Output $Result
        $GroupEligibleMembers += $Result
    }
    Catch {
        #Write-Output $_
        Write-Output ("Could not get PIM memberships for group " + $Group.displayName) -ForegroundColor Red
    }
}
$GroupEligibleMembers | ConvertTo-Json -Depth 10 | Out-File $File -Force

#Export DirectoryRoles
$URI = $GraphURI + "/roleManagement/directory/roleDefinitions"
$File = ($DataFolder + "\" + $FilePrefix + ".DirectoryRoles.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export DirectoryRoleAssignments
$URI = $GraphURI + "/roleManagement/directory/roleAssignments"
$File = ($DataFolder + "\" + $FilePrefix + ".DirectoryRoleAssignments.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export Eligible Directory Roles Members
$URI = $GraphURI + "/roleManagement/directory/roleEligibilitySchedules"
$File = ($DataFolder + "\" + $FilePrefix + ".DirectoryRoleEligibleMembers.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export Access Packages
$URI = $GraphURI + '/identityGovernance/entitlementManagement/accessPackages'
$File = ($DataFolder + "\" + $FilePrefix + ".AccessPackages.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export AccessPackageResourceRole
#Export van AccessPackage -> Permission
$URI = $GraphURI + '/identityGovernance/entitlementManagement/accessPackages?$expand=accessPackageResourceRoleScopes($expand=accessPackageResourceRole,accessPackageResourceScope)'
$File = ($DataFolder + "\" + $FilePrefix + ".AccessPackageResourceRole.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File

#Export AccessPackageResourceRole
#Export van User -> AccessPackage
$URI = $GraphURI + "/identityGovernance/entitlementManagement/accessPackageAssignments"
$File = ($DataFolder + "\" + $FilePrefix + ".AccessPackageAssignments.Json")
Write-Output $URI
Invoke-FGGetRequestToFile  -URI $URI -file $File


#################################################################################################################
# Stop
#################################################################################################################

$DataStorageTenantName = Get-AutomationVariable -Name DataStorage-TenantName
$DataStorageAzureSubscription = Get-AutomationVariable -Name DataStorage-AzureSubscription
$DataStorageResourceGroup = Get-AutomationVariable -Name DataStorage-ResourceGroup
$DataStorageStorageAccountName = Get-AutomationVariable -Name DataStorage-StorageAccountName
$DataStorageDataContainer = Get-AutomationVariable -Name DataStorage-DataContainer
$DataStorageTranscriptContainer = Get-AutomationVariable -Name DataStorage-TranscriptContainer
$DataStorageHistoryContainer = Get-AutomationVariable -Name DataStorage-HistoryContainer
$DataStorageKeepHistory = Get-AutomationVariable -Name DataStorage-KeepHistory


#Connect to Storage Account
Try {
    Connect-AzAccount -Tenant $DataStorageTenantName -Subscription $DataStorageAzureSubscription -Identity
    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $DataStorageResourceGroup -Name $DataStorageStorageAccountName
    $Context = $StorageAccount.Context
}
Catch {
    $_
}

#Upload Files to Storage Account
$Files = Get-ChildItem -Path $DataFolder -Filter *.json
Foreach ($File in $Files) {
    Set-AzStorageBlobContent -File $File.FullName -Container $DataStorageDataContainer -Blob $File.Name -Context $Context -Force
}

#Keep History
if ($DataStorageKeepHistory) {

    #Create a ZIP file for History
    $HistoryZip = $env:TEMP + "\" + $FilePrefix + "." + (Get-Date -Format "yyyy-MM-ddTHH-mm-ss") + ".zip"
    Compress-Archive -Path $DataFolder -DestinationPath $HistoryZip
    $Zip = Get-Item -Path $HistoryZip
    
    #Upload it
    Set-AzStorageBlobContent -File $Zip.FullName -Container $DataStorageHistoryContainer -Blob $Zip.Name -Context $Context -Force
    
    #Remove it from Temp
    Remove-Item -Path $Zip.FullName -Force
}

#Remove Temp Files
Remove-Item -Path $DataFolder -Recurse -force

#Stop Transcript
Stop-Transcript

#Upload the Transcript
Set-AzStorageBlobContent -File ($env:TEMP + "\" + $TranscriptFileName) -Container $DataStorageTranscriptContainer -Blob $TranscriptFileName -Context $Context

#Remove local copy of transcript
Remove-Item -Path ($env:TEMP + "\" + $TranscriptFileName) -Force