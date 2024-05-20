#################################################################################################################
# Start
# Notes: 
#
# Script need a PAT with readrights read permissions on organisation(s).
#
# https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/memberships/list?view=azure-devops-rest-7.1&tabs=HTTP#all-members-of-a-group
#################################################################################################################

Import-Module FortigiGraph -MinimumVersion 1.0.20240206.1453

#File Prefix
$FilePrefix = "DevOps"

#Set Temp Date Folder
$DataFolder = ($env:TEMP+"\"+$FilePrefix+".Export")

#Test Data Folder Path and create export folder
If (!(Test-Path -Path $DataFolder)) {
    New-Item -Path $DataFolder -ItemType Directory
}

$TranscriptFileName = ($FilePrefix+".Export.Transcript_" + (Get-Date -format yyyy-MM-dd-HHmm) + ".txt")
Start-Transcript -Path ($env:TEMP + "\" + $TranscriptFileName) -Force

#Set the export date and time in a JSON
$DateFile = @{
    "Date" = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
} 
$DateFile | ConvertTo-Json | Out-File ($DataFolder+"\"+$FilePrefix+".DateFile.Json") -Force

#################################################################################################################
# Script
#################################################################################################################

#connect to DevOps
az login --identity
$accessToken = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query "accessToken" --output tsv
$headers = @{
    Accept = "application/json"
    Authorization = "Bearer $accessToken"
}

#get list of all orgs
$orgNamesString = Get-AutomationVariable -Name DevOps-Organisations
# convert string to array 
#$orgNamesString = "nexxbiz"
#convert to array
$orgNames = $orgNamesString.Split(",") 
 
# Create custom object to store user information
$userObjects = @()
Foreach ($orgname in $orgNames) {

    $baseUrl = "https://vssps.dev.azure.com/$orgName/_apis"
 
    # Get users
    $usersUrl = "$baseUrl/graph/users?api-version=7.1-preview.1"
    $usersResponse = Invoke-RestMethod -Uri $usersUrl -Headers $headers
    $users = $usersResponse.value
    #$users
    # Get groups
    $groupsUrl = "$baseUrl/graph/groups?api-version=7.1-preview.1"
    $groupsResponse = Invoke-RestMethod -Uri $groupsUrl -Headers $headers
    $groups = $groupsResponse.value
    #$groups

    # Create a hashtable to store project names indexed by project IDs
    $groupNames = @{}
    foreach ($group in $groups) {
        $groupNames[$group.descriptor] = $group.principalName
    }


    # Create custom object to store user information
    foreach ($user in $users) {
        if($user.metaType){
        #get groups of the user
        $groupsUrl = "$baseUrl/graph/Memberships/"+$user.descriptor+"?api-version=7.1-preview.1"
        $userGroups = Invoke-RestMethod -Uri $groupsUrl -Headers $headers
        
        # foreach all orgs the user has rights to and put it in an opbject
        $groupObject = @()
        if ($userGroups.value){
            foreach ($group in $userGroups.value) {
                if ($group.containerDescriptor){
                    $groupdescriptor = $group.containerDescriptor
                    $groupName = $groupNames[$groupdescriptor]
                    $parts = $groupName -split "\\|\[|\]" | Where-Object { $_ -ne '' }
                    $customObject = [PSCustomObject]@{
                    projectName = $parts[0]
                    groupName = $parts[1]
                    }
                }   
                $groupObject += $customObject
            }
        }
            # make the user object with all info 
            $customObject = [PSCustomObject]@{ 
                Username = $user.principalName 
                Email = $user.mailAddress
                typeUser = $user.subjectKind
                metaType = $user.metaType
                alias = $user.directoryAlias
                organisation = $orgname
                "Groups" = $groupObject

            }
            $userObjects += $customObject
        }
    }
}

#Export user Packages
$userFile = ($DataFolder+"\"+$FilePrefix+".users.json")
$userObjects | ConvertTo-Json -Depth 5 | out-file -Path $userFile

#################################################################################################################
# Stop
#################################################################################################################

# export to storage account
$TenantName = Get-AutomationVariable -Name TenantName
$DataStorageAzureSubscription = Get-AutomationVariable -Name DataStorage-AzureSubscription
$DataStorageResourceGroup = Get-AutomationVariable -Name DataStorage-ResourceGroup
$DataStorageStorageAccountName = Get-AutomationVariable -Name DataStorage-StorageAccountName
$DataStorageDataContainer = Get-AutomationVariable -Name DataStorage-DataContainer
$DataStorageTranscriptContainer = Get-AutomationVariable -Name DataStorage-TranscriptContainer
$DataStorageHistoryContainer = Get-AutomationVariable -Name DataStorage-HistoryContainer
$DataStorageKeepHistory = Get-AutomationVariable -Name DataStorage-KeepHistory

#Connect to Storage Account
Connect-AzAccount -Tenant $TenantName -Subscription $DataStorageAzureSubscription -Identity
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $DataStorageResourceGroup -Name $DataStorageStorageAccountName
$Context = $StorageAccount.Context

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

