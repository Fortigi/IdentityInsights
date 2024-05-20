#################################################################################################################
# Start
# Notes: 
#
# Script need a mongp API account with read permissions on organisation.
# Also the IP of the automation account need to be on the whitlist!
#################################################################################################################

Import-Module FortigiGraph -MinimumVersion 1.0.20240206.1453

#File Prefix
$FilePrefix = "Mongo"

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

#connect to Mongo

# Set your MongoDB Atlas API key
$apiKey = Get-AutomationVariable -Name Mongo-apiKey

# Set the Atlas group ID (organization ID)
$groupId = Get-AutomationVariable -Name Mongo-organizationID

# get all org
$orgResults = curl -i -u $apiKey --digest "https://cloud.mongodb.com/api/public/v1.0/orgs/"
$orgjsonContent = $orgResults | Select-String -Pattern '{.*}' | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
# Convert org JSON content to PowerShell objects
$orgs = $orgjsonContent | ConvertFrom-Json

#get all project
$projectResults = curl -i -u $apiKey --digest "https://cloud.mongodb.com/api/public/v1.0/orgs/$groupId/groups"
$projectjsonContent = $projectResults | Select-String -Pattern '{.*}' | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
# Convert project JSON content to PowerShell objects
$projects = $projectjsonContent | ConvertFrom-Json

#get all users in Organisation
$userResults = curl -i -u $apiKey --digest "https://cloud.mongodb.com/api/public/v1.0/orgs/$groupId/users"
$userjsonContent = $userResults | Select-String -Pattern '{.*}' | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
# Convert user JSON content to PowerShell objects
$users = $userjsonContent | ConvertFrom-Json

#get all API in Organisation
$apiResults = curl -i -u $apiKey --digest "https://cloud.mongodb.com/api/public/v1.0/orgs/$groupId/apiKeys"
$apijsonContent = $apiResults | Select-String -Pattern '{.*}' | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
# Convert user JSON content to PowerShell objects
$apis = $apijsonContent | ConvertFrom-Json

# Create a hashtable to store org names indexed by project IDs
$orgNames = @{}
foreach ($org in $orgs.results) {
    $orgNames[$org.id] = $org.name
}

# Create a hashtable to store project names indexed by project IDs
$projectNames = @{}
foreach ($project in $projects.results) {
    $projectNames[$project.id] = $project.name
}

# Create custom object to store user information
$userObjects = @()
# Join user list and project list
foreach ($user in $users.results) {
    # foreach all orgs the user has rights to and put it in an opbject
    $orgroleObject = @()
    if ($user.roles.orgId){
        foreach ($orgrole in $user.roles | Where-Object {$_.orgId} ) {
            if ($orgrole.orgId){
                $orgId = $orgrole.orgId
                $orgName = $orgNames[$orgId]
                $orgrole = $orgrole.rolename
             
                $customObject = [PSCustomObject]@{ 
                orgName = $orgName
                orgRole = $orgrole
                }
            }   
            $orgroleObject += $customObject
        }
    }
    # foreach all orgs the user has rights to and put it in an opbject
    $projectroleObject = @()
    if ($user.roles.groupId){
        foreach ($projectRole in $user.roles | Where-Object {$_.groupId} )  {
            if ($projectRole.groupId){
                $projectId = $projectRole.groupId
                $projectName = $projectNames[$projectId]
                $projectrole = $projectRole.rolename
             
                $customObject = [PSCustomObject]@{ 
                projectName = $projectName
                projectRole = $projectrole
                }
            }   
            $projectroleObject += $customObject
        }
    }
    # make the user object with all info 
    $customObject = [PSCustomObject]@{ 
        Username = $user.username 
        Email = $user.emailAddress
        FirstName = $user.firstName 
        LastName = $user.lastName
        "Last login" = $user.lastAuth
        "Organisation Roles" = $orgroleObject
        "Project Roles" = $projectroleObject
        
    }
    $userObjects += $customObject  
}

# Create custom object to store API information
$apibjects = @()
# Join user list and project list
foreach ($api in $apis.results) {
    # foreach all orgs the user has rights to and put it in an opbject
    $orgroleObject = @()
    if ($api.roles.orgId){
        foreach ($orgrole in $api.roles | Where-Object {$_.orgId} ) {
            if ($orgrole.orgId){
                $orgId = $orgrole.orgId
                $orgName = $orgNames[$orgId]
                $orgrole = $orgrole.rolename
             
                $customObject = [PSCustomObject]@{ 
                orgName = $orgName
                orgRole = $orgrole
                }
            }   
            $orgroleObject += $customObject
        }
    }
    # foreach all orgs the user has rights to and put it in an opbject
    $projectroleObject = @()
    if ($api.roles.groupId){
        foreach ($projectRole in $api.roles | Where-Object {$_.groupId} )  {
            if ($projectRole.groupId){
                $projectId = $projectRole.groupId
                $projectName = $projectNames[$projectId]
                $projectrole = $projectRole.rolename
             
                $customObject = [PSCustomObject]@{ 
                projectName = $projectName
                projectRole = $projectrole
                }
            }   
            $projectroleObject += $customObject
        }
    }
    # make the user object with all info 
    $customObject = [PSCustomObject]@{ 
        Name = $api.desc 
        PublicKey = $api.publicKey
        "Organisation Roles" = $orgroleObject
        "Project Roles" = $projectroleObject
        
    }
    $apibjects += $customObject  
}

#Export user Packages
$userFile = ($DataFolder+"\"+$FilePrefix+".users.json")
$userObjects | ConvertTo-Json -Depth 5 | out-file -Path $userFile

#Export API Packages
$apiFile = ($DataFolder+"\"+$FilePrefix+".api.json")
$apibjects | ConvertTo-Json -Depth 5 | out-file -Path $apiFile

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