#Powershell collector script for Infoblox API to vRops Suite-api
#v1.0 vMan.ch, 15.06.2018 - Initial Version
<#

    .SYNOPSIS

    Collecting metric / state data from infoblox and pushes it into vRops for monitoring as a new ResourceKind.

    Script requires Powershell v3 and above.

    Run the command below to store user and pass in secure credential XML for each environment

        $cred = Get-Credential
        $cred | Export-Clixml -Path "E:\vRops\Infoblox\config\infoblox.xml"

Usage .\Infoblox-Monitor.ps1  -vRopsAddress 'vRops.vman.ch' -infoblox 'infoblox.vman.ch' -vRopsCreds 'vRops' -InfobloxCreds 'Infoblox'

#>


param
(
    [String]$vRopsAddress,
    [String]$infoblox,
    [String]$vRopsCreds,
    [String]$InfobloxCreds
)

$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName

if($vRopsCreds -gt ""){

    $vRopsCred = Import-Clixml -Path "$ScriptPath\config\$vRopsCreds.xml"

    }
    else
    {
    echo "vRops Credentials not specified, stop hammer time!"
    Exit
    }

if($InfobloxCreds -gt ""){

    $InfobloxCred = Import-Clixml -Path "$ScriptPath\config\$InfobloxCreds.xml"

    }
    else
    {
    echo "Infoblox Credentials not specified, stop hammer time!"
    Exit
    }


#Functions

#Get vRops ResourceID from Name
Function GetObject([String]$vRopsObjName, [String]$resourceKindKey, [String]$vRopsServer, $vRopsCredentials){

    $vRopsObjName = $vRopsObjName -replace ' ','%20'

    [xml]$Checker = Invoke-RestMethod -Method Get -Uri "https://$vRopsServer/suite-api/api/resources?resourceKind=$resourceKindKey&name=$vRopsObjName" -Credential $vRopsCredentials -Headers $header -ContentType $ContentType

#Check if we get 0

    if ([Int]$Checker.resources.pageInfo.totalCount -eq '0'){

    Return $CheckerOutput = ''

    }

    else {

        # Check if we get more than 1 result and apply some logic
            If ([Int]$Checker.resources.pageInfo.totalCount -gt '1') {

                $DataReceivingCount = $Checker.resources.resource.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'

                    If ($DataReceivingCount.count -gt 1){

                     If ($Checker.resources.resource.ResourceKey.name -eq $vRopsObjName){

                        ForEach ($Result in $Checker.resources.resource){

                            IF ($Result.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'){

                            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                            Return $CheckerOutput
                    
                            }   
                        }

                      }
                    }
            
                    Else 
                    {

                    ForEach ($Result in $Checker.resources.resource){

                        IF ($Result.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'){

                            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                            Return $CheckerOutput
                    
                        }   
                    }
            }  
         }

        else {
    
            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Checker.resources.resource.identifier; resourceKindKey=$Checker.resources.resource.resourceKey.resourceKindKey}

            Return $CheckerOutput

            }
        }
}

#Function to create new vRops InfoBloxNODE
Function CreatevRopsObject([String]$vRopsServer, $CreateRopsObject, $vRopsCredentials){

[xml]$CreateXML = @('<ops:resource xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
   <ops:description>Infoblox Node</ops:description>
   <ops:resourceKey>
      <ops:name>{0}</ops:name>
      <ops:adapterKindKey>INFOBLOX</ops:adapterKindKey>
      <ops:resourceKindKey>InfoBloxNODE</ops:resourceKindKey>
      <ops:resourceIdentifiers>
         <ops:resourceIdentifier>
            <ops:identifierType name="entityName" dataType="STRING" isPartOfUniqueness="true" />
            <ops:value>{0}</ops:value>
            </ops:resourceIdentifier>
      </ops:resourceIdentifiers>
   </ops:resourceKey>
   <ops:resourceStatusStates />
   <ops:dtEnabled>true</ops:dtEnabled>
</ops:resource>' -f $CreateRopsObject
)

 
#Create URL string for voke-RestMethod
$Createurl = 'https://'+$vRopsServer+'/suite-api/api/resources/adapterkinds/OPENAPI'
 
#Send Attribute data to vRops.
$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')
#$header.Add("X-vRealizeOps-API-use-unsupported", 'true')
 
try {
        $result = Invoke-RestMethod -Method POST -uri $Createurl -Body $CreateXML -Credential $vRopsCredentials -ContentType $ContentType -Headers $header
}
catch {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
}

}

#Get Date / Time for vRops
[DateTime]$NowDate = (Get-date)
[int64]$NowDateEpoc = (([DateTimeOffset](Get-Date)).ToUniversalTime().ToUnixTimeMilliseconds())

#Take all certs.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls

#Stuff for Invoke-RestMethod
$ContentType = "application/xml"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')
$header.Add("User-Agent", 'InfobloxHealthExtractor/1.0')
 

#Collect NodeInfo

$nodeinfo = Invoke-RestMethod -Method Get -Uri "https://$infoblox/wapi/v2.7/member?_return_fields=node_info" -Credential $InfobloxCred -Headers $header -ContentType $ContentType

#GetProperties

$InfoBloxProperties = @()
$InfoBloxMetrics = @()
$InfoBloxStatus = @()

ForEach ($blox in $nodeinfo.list.value){

    $Name = $blox.'_ref'.Substring(($blox.'_ref'.IndexOf(":"))+1)

    $resourceid = GetObject $Name 'InfoBloxNODE' $vRopsAddress $vRopsCred

    If ($resourceid -eq ''){
    
        #Debug
        #Write-Host $Name 'Object does not exist in vRops, creating it now'

        CreatevRopsObject $vRopsAddress $Name $vRopsCred

        #Debug
        #Write-Host 'Searching again for' $Name

        $resourceid = GetObject $Name 'InfoBloxNODE' $vRopsAddress $vRopsCred

        #Debug
        #Write-host 'Found it' $resourceid.resourceId

        }

    ForEach ($Val in $blox){

    $DISK_USAGE = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'DISK_USAGE' | select 'description').Description
    $MEMORY = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'MEMORY' | select 'description').Description
    $SWAP_USAGE = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'SWAP_USAGE' | select 'description').Description
    $DB_OBJECT = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'DB_OBJECT' | select 'description').Description
    $DISCOVERY_CAPACITY = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'DISCOVERY_CAPACITY' | select 'description').Description
    $CPU_USAGE = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'CPU_USAGE' | select 'description').Description 

        $InfoBloxProperties += New-Object PSObject -Property @{

            NAME = $Name
            ResourceID = $resourceid.resourceId
            NODE_STATUS = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'NODE_STATUS' | select 'description').Description
            DISK_USAGE = $DISK_USAGE.Substring(($DISK_USAGE.IndexOf("- "))+2)
            ENET_LAN = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'ENET_LAN' | select 'description').Description
            REPLICATION = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'REPLICATION' | select 'description').Description
            DB_OBJECT = $DB_OBJECT.Substring(($DB_OBJECT.IndexOf("- "))+2)
            NTP_SYNC = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'NTP_SYNC' | select 'description').Description
            OSPF = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'OSPF' | select 'description').Description
            OSPF6 = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'OSPF6' | select 'description').Description
            BGP = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'BGP' | select 'description').Description
            BFD = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'BFD' | select 'description').Description
            CORE_FILES = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'CORE_FILES' | select 'description').Description
            MEMORY = $MEMORY.Substring(($MEMORY.IndexOf("- "))+2)
            SWAP_USAGE = $SWAP_USAGE.Substring(($SWAP_USAGE.IndexOf("- "))+2)
            DISCOVERY_CAPACITY = $DISCOVERY_CAPACITY.Substring(($DISCOVERY_CAPACITY.IndexOf("- "))+2)
            VPN_CERT = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'VPN_CERT' | select 'description').Description

             
        }

        $InfoBloxMetrics += New-Object PSObject -Property @{

            NAME = $Name
            ResourceID = $resourceid.resourceId
            DISK_USAGE = [regex]::Matches($DISK_USAGE, "\d+(?!.*\d+)").value
            CPU_USAGE = [regex]::Matches($CPU_USAGE, "\d+(?!.*\d+)").value | select -unique
            MEMORY = [regex]::Matches($MEMORY, "\d+(?!.*\d+)").value
            SWAP_USAGE = [regex]::Matches($SWAP_USAGE, "\d+(?!.*\d+)").value
            DISCOVERY_CAPACITY = [regex]::Matches($DISCOVERY_CAPACITY, "\d+(?!.*\d+)").value
            DB_OBJECT = [regex]::Matches($DB_OBJECT, "\d+(?!.*\d+)").value

        }

        $InfoBloxStatus += New-Object PSObject -Property @{

            NAME = $Name
            ResourceID = $resourceid.resourceId
            NODE_STATUS = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'NODE_STATUS' | select 'status').Status
            DISK_USAGE = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'DISK_USAGE' | select 'status').Status
            ENET_LAN = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'ENET_LAN' | select 'status').Status
            REPLICATION = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'REPLICATION' | select 'status').Status
            DB_OBJECT = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'DB_OBJECT' | select 'status').Status
            NTP_SYNC = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'NTP_SYNC' | select 'status').Status
            CPU_USAGE = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'CPU_USAGE' | select 'status').Status | select -unique
            OSPF = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'OSPF' | select 'status').Status
            OSPF6 = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'OSPF6' | select 'status').Status
            BGP = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'BGP' | select 'status').Status
            BFD = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'BFD' | select 'status').Status
            CORE_FILES = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'CORE_FILES' | select 'status').Status
            MEMORY = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'MEMORY' | select 'status').Status
            SWAP_USAGE = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'SWAP_USAGE' | select 'status').Status
            DISCOVERY_CAPACITY = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'DISCOVERY_CAPACITY' | select 'status').Status
            VPN_CERT = ($Val.node_info.list.Value.service_status.list.Value | where service -eq 'VPN_CERT' | select 'status').Status

        }

    }
}


#Collect ServiceInfo

$Serviceinfo = Invoke-RestMethod -Method Get -Uri "https://$infoblox/wapi/v2.7/member?_return_fields=service_status" -Credential $InfobloxCred -Headers $header -ContentType $ContentType

$InfoBloxServices = @()

ForEach ($bloxService in $Serviceinfo.list.value){

    $Name = $bloxService.'_ref'.Substring(($bloxService.'_ref'.IndexOf(":"))+1)

    $resourceid = GetObject $Name 'INFOBLOXNODE' $vRopsAddress $vRopsCred

    ForEach ($Serv in $bloxService.service_status.list.Value){

        #Changeing the Service states to metrics

        #INACTIVE = 0
        #WORKING = 1
        #UNKNOWN = 2
        #Everything else = -1

        $InfoBloxServices += New-Object PSObject -Property @{

            NAME = $Name
            ResourceID = $resourceid.resourceId
            SERVICE = $Serv.Service
            STATUS = $Serv.Status
            CODE = If ($Serv.Status -eq 'INACTIVE'){'0'}ElseIf($Serv.Status -eq 'WORKING'){'1'}ElseIf($Serv.Status -eq 'UNKNOWN'){'2'}Else {'-1'}
             
        }
    }
}


#Check if the node exists




#Push in Properties

    ForEach ($PropertyInsert in $InfoBloxProperties){

        #Debug
        #Write-Host 'Inserting Node Properties for' $PropertyInsert.Name

        [xml]$PropertyXML = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ops:property-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
            <ops:property-content statKey="INFOBLOX|VALUES|OSPF">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{1}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|OSPF6">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{2}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|CORE_FILES">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{3}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|NTP_SYNC">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{4}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|DISK_USAGE">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{5}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|BGP">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{6}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|MEMORY">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{7}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|VPN_CERT">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{8}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|ENET_LAN">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{9}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|BFD">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{10}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|DISCOVERY_CAPACITY">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{11}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|DB_OBJECT">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{12}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|SWAP_USAGE">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{13}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|NODE_STATUS">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{14}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|VALUES|REPLICATION">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{15}</ops:values>
            </ops:property-content>
        </ops:property-contents>' -f $NowDateEpoc,
                                     $PropertyInsert.OSPF,
                                     $PropertyInsert.OSPF6,
                                     $PropertyInsert.CORE_FILES,
                                     $PropertyInsert.NTP_SYNC,
                                     $PropertyInsert.DISK_USAGE,
                                     $PropertyInsert.BGP,
                                     $PropertyInsert.MEMORY,
                                     $PropertyInsert.VPN_CERT,
                                     $PropertyInsert.ENET_LAN,
                                     $PropertyInsert.BFD,
                                     $PropertyInsert.DISCOVERY_CAPACITY,
                                     $PropertyInsert.DB_OBJECT,
                                     $PropertyInsert.SWAP_USAGE,
                                     $PropertyInsert.NODE_STATUS,
                                     $PropertyInsert.REPLICATION
        )


#Create URL string for Invoke-RestMethod

$vRopsPropertyURL = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+$PropertyInsert.Resourceid+'/properties'

Invoke-RestMethod -Method POST -uri $vRopsPropertyURL -Body $PropertyXML -Credential $vRopsCred -ContentType "application/xml;charset=utf-8"

Remove-Variable vRopsPropertyURL -ErrorAction SilentlyContinue
Remove-Variable PropertyXML -ErrorAction SilentlyContinue
Remove-Variable PropertyInsert -ErrorAction SilentlyContinue
}


#Push in Metrics

    ForEach ($MetricInsert in $InfoBloxMetrics){

        #Debug
        #Write-Host 'Inserting Node Metrics for' $MetricInsert.Name

        [xml]$MetricXML = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <ops:stat-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
                <ops:stat-content statKey="CPU|Usage">
                  <ops:timestamps>{0}</ops:timestamps>
                  <ops:data>{1}</ops:data>
                  <ops:unit>%</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="MEM|Usage">
                  <ops:timestamps>{0}</ops:timestamps>
                    <ops:data>{2}</ops:data>
                    <ops:unit>%</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="DISK|Usage">
                  <ops:timestamps>{0}</ops:timestamps>
                    <ops:data>{3}</ops:data>
                    <ops:unit>%</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="SWAP|Usage">
                  <ops:timestamps>{0}</ops:timestamps>
                    <ops:data>{4}</ops:data>
                    <ops:unit>%</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="DISCOVERY|Usage">
                  <ops:timestamps>{0}</ops:timestamps>
                    <ops:data>{5}</ops:data>
                    <ops:unit>%</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="DB_OBJECT|Usage">
                  <ops:timestamps>{0}</ops:timestamps>
                    <ops:data>{6}</ops:data>
                    <ops:unit>%</ops:unit>
                </ops:stat-content>
            </ops:stat-contents>' -f $NowDateEpoc,
                                     $MetricInsert.CPU_USAGE,
                                     $MetricInsert.MEMORY,
                                     $MetricInsert.DISK_USAGE,
                                     $MetricInsert.SWAP_USAGE,
                                     $MetricInsert.DISCOVERY_CAPACITY,
                                     $MetricInsert.DB_OBJECT
            )


$vRopsMetricURL = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+$MetricInsert.Resourceid+'/stats'

Invoke-RestMethod -Method POST -uri $vRopsMetricURL -Body $MetricXML -Credential $vRopsCred -ContentType "application/xml;charset=utf-8"

Remove-Variable vRopsMetricURL -ErrorAction SilentlyContinue
Remove-Variable MetricXML -ErrorAction SilentlyContinue
Remove-Variable MetricInsert -ErrorAction SilentlyContinue
}

    ForEach ($StatusInsert in $InfoBloxStatus){

        #Debug
        #Write-Host 'Inserting Node Status for' $StatusInsert.Name

        [xml]$StatusXML = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ops:property-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
            <ops:property-content statKey="INFOBLOX|STATUS|OSPF">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{1}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|OSPF6">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{2}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|CORE_FILES">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{3}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|NTP_SYNC">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{4}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|DISK_USAGE">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{5}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|BGP">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{6}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|MEMORY">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{7}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|VPN_CERT">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{8}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|ENET_LAN">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{9}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|BFD">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{10}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|DISCOVERY_CAPACITY">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{11}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|DB_OBJECT">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{12}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|SWAP_USAGE">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{13}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|NODE_STATUS">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{14}</ops:values>
            </ops:property-content>
            <ops:property-content statKey="INFOBLOX|STATUS|REPLICATION">
                <ops:timestamps>{0}</ops:timestamps>
                <ops:values>{15}</ops:values>
            </ops:property-content>
        </ops:property-contents>' -f $NowDateEpoc,
                                     $StatusInsert.OSPF,
                                     $StatusInsert.OSPF6,
                                     $StatusInsert.CORE_FILES,
                                     $StatusInsert.NTP_SYNC,
                                     $StatusInsert.DISK_USAGE,
                                     $StatusInsert.BGP,
                                     $StatusInsert.MEMORY,
                                     $StatusInsert.VPN_CERT,
                                     $StatusInsert.ENET_LAN,
                                     $StatusInsert.BFD,
                                     $StatusInsert.DISCOVERY_CAPACITY,
                                     $StatusInsert.DB_OBJECT,
                                     $StatusInsert.SWAP_USAGE,
                                     $StatusInsert.NODE_STATUS,
                                     $StatusInsert.REPLICATION
        )

$vRopsStatusURL = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+$StatusInsert.Resourceid+'/properties'

Invoke-RestMethod -Method POST -uri $vRopsStatusURL -Body $StatusXML -Credential $vRopsCred -ContentType "application/xml;charset=utf-8"

Remove-Variable vRopsStatusURL -ErrorAction SilentlyContinue
Remove-Variable StatusXML -ErrorAction SilentlyContinue


#Pushing ServiceStatus

    #Debug
    #Write-Host 'Inserting Service Status for' $StatusInsert.Name

      $InfoServiceStatusXML = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ops:stat-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">')

    ForEach ($InfoService in $InfoBloxServices | where {$_.Resourceid -eq $StatusInsert.Resourceid}){

      $InfoServiceStatusXML += @('<ops:stat-content statKey="SERVICE|'+$InfoService.SERVICE+'|Status">
                                  <ops:timestamps>'+$NowDateEpoc+'</ops:timestamps>
                                  <ops:data>'+$InfoService.CODE+'</ops:data>
                                  <ops:unit>num</ops:unit>
                                  </ops:stat-content>')
}

      $InfoServiceStatusXML += @('</ops:stat-contents>')

[xml]$InfoServiceStatusXML = $InfoServiceStatusXML

$vRopsInfoServiceStatusURL = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+$StatusInsert.Resourceid+'/stats'

Invoke-RestMethod -Method POST -uri $vRopsInfoServiceStatusURL -Body $InfoServiceStatusXML -Credential $vRopsCred -ContentType "application/xml;charset=utf-8"

#Debug
#Echo $InfoServiceStatusXML.'stat-contents'.'stat-content'

Remove-Variable vRopsStatusURL -ErrorAction SilentlyContinue
Remove-Variable StatusInsert -ErrorAction SilentlyContinue
Remove-Variable InfoServiceStatusXML -ErrorAction SilentlyContinue
Remove-Variable vRopsInfoServiceStatusURL -ErrorAction SilentlyContinue

}
