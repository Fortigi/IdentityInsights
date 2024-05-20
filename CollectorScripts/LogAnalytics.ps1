#################################################################################################################
# Start
#################################################################################################################

#File Prefix
$FilePrefix = "LogAnalytics"

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

#Connect to Graph if not yet connected
$TenantName = Get-AutomationVariable -Name TenantName
$LogAnalyticsWorkspaceID = Get-AutomationVariable -Name LogAnalytics-WorkspaceID
$LogAnalyticsAzureSubscription = Get-AutomationVariable -Name LogAnalytics-AzureSubscription

Connect-AzAccount -Tenant $TenantName -Subscription $LogAnalyticsAzureSubscription -Identity

$ADLoginsQuery = "SecurityEvent | where TimeGenerated > ago (1000d) | where EventID == '4624' | where AccountType == 'User' | extend UserName = tostring(split(Account, '\\')[-1]) | summarize max(TimeGenerated) by UserName"
$ADLogins = Invoke-AzOperationalInsightsQuery -WorkspaceId $LogAnalyticsWorkspaceID -Query $ADLoginsQuery
$ADLogins | ConvertTo-Json -Depth 10 | Out-File ($DataFolder+"\"+$FilePrefix+".ADLogins.Json") -Force


#################################################################################################################
# Stop
#################################################################################################################

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