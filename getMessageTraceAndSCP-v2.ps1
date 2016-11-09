# Script to get last N hours of meessages from Exchange Online
# and scp it to the logging server for log analysis
# This script should be scheduled to run every hour
#
# Author: Khizer Naeem
# Creation Date: 07/11/2016
# Last Revision: 09/11/2016

# Get the logs up to how many hours ago?
# Setting this to 0 will make the logs up till most recent
# Last hour's data is very immature and incomplete in some cases
# It is recommended to set this to atlease 1
$NumOfHoursTo = 2
# Get the logs from how many hours ago?
$NumOfHoursFrom = 4

$OutPutCSV = "TraceLog.csv"
$SCPDestination = "o365logs@192.168.2.222:/home/o365logs/"
$sshKey = "ssh.ppk"
$MSPasswordFile = "password.txt"

# Find out what is our directory
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path $ScriptPath

# Create timestamp to be included in the CSV file name
# This will decide how many csv files you keep before you sart overwriting
# For example If we run this script every hour and use the format "dd-h",
# Where dd is day of the month and h is Hour of the day,
# we will be keeping one months of logs i.e 30*24=720
$CSVTimeStamp = get-date -Format "dd-h"

# Don't show warning messages
$WarningPreference = "SilentlyContinue"

# Remove the CSVFile if it is already there, to avoid appending to an existing file.
# Its important to remove the file here since the Export-Csv is run with -Append.
If (Test-Path "$ScriptDir\$CSVTimeStamp-$OutPutCSV"){
	Remove-Item "$ScriptDir\$CSVTimeStamp-$OutPutCSV"
}

# Start the Session with Exchange Online
$UserName = "admin@hbmsu.onmicrosoft.com"
$Password = cat "$ScriptDir\$MSPasswordFile" | convertto-securestring
$Credentials = new-object -typename System.Management.Automation.PSCredential -ArgumentList $UserName,$Password
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell/ -Credential $Credentials -Authentication Basic -AllowRedirection
Import-PSSession $Session -DisableNameChecking -verbose:$false | Out-Null

# Create the date/time range
[DateTime]$DateTo = Get-Date (Get-Date).AddHours($NumOfHoursTo * -1).ToUniversalTime()  -Format g
[DateTime]$DateFrom = Get-Date (Get-Date).AddHours($NumOfHoursFrom * -1).ToUniversalTime()  -Format g

# Create timestamp to be included in the CSV file name
# This will decide how many csv files you keep before you sart overwriting
# We are using the "day of the month" and "Hour of the day"
$CSVTimeStamp = get-date -Format "dd-h"


Write-Host "Collecting logs From: $DateFrom ~ To: $DateTo (UTC)"

# Start the paging iteration loop 1-1000 (Max of 1000 pages allowed)
$FoundCount = 0
For($i = 1; $i -le 1000; $i++) {
    # Get the 5000 messges from this page
    $Messages = Get-MessageTrace -StartDate $DateFrom -EndDate $DateTo -PageSize 5000 -Page $i
    # Export messages in csv format and append it to the output file
    # While counting the entries
    If($Messages.count -gt 0) {
	Write-Host "Processing $($Messages.count) Messages"
        $Entries = $Messages | Select Received, SenderAddress, RecipientAddress, Subject, Status, FromIP, Size, MessageId, MessageTraceId 
        $Entries | Export-Csv "$ScriptDir\$CSVTimeStamp-$OutPutCSV" -NoTypeInformation -Append -Encoding "UTF8"
	$FoundCount += $Entries.Count
    }
    Else {
        # Show how many messages we got
        Write-Host "Finisehd Processing all the messages"
	Write-Host "$FoundCount Entries written to $ScriptDir\$CSVTimeStamp-$OutPutCSV"

        # Break when no message left
        Break
    }
}


# SCP the output csv file to the logging server
Start-Process "$ScriptDir\pscp.exe" -Wait -ArgumentList ("-scp -i `"$ScriptDir\$sshKey`" -hostkey `"16:65:00:12:b5:a7:af:0e:c4:75:4d:5a:d4:c6:bd:6c`" `"$ScriptDir\$OutPutCSV`" `"$SCPDestination`"")
Write-Host "Secure Copied  $ScriptDir\$CSVTimeStamp-$OutPutCSV to $SCPDestination"

# End the PS Session
Remove-PSSession $Session