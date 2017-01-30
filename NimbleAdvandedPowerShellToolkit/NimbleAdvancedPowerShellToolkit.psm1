@{
   FormatsToProcess = 'NimbleAdvancedPowerShellToolkit.Format.ps1xml'
   RequiredModules = @('NimblePowerShellToolkit')
 }

<#
.SYNOPSIS 
Creates a new Initiator Group on the Nimble Array.

.DESCRIPTION
An Initiator Group is used to define access for a specific server to access a set of Nimble Storage Volumes. 
Commonly the name of the Initiator Group will match the hostname of the server and will act as a container for
the Initiator objects specific to this server which can be set using the followup commnd New-NimInitiator. This
command will ONLY create a new Initiator group if the requisite tests pass such as verification that the host 
contains initators which can communicate with the Nimble Array via the appropriate protocol. To override these 
checks, and force the creation of the Initiator Group without these checks, use the commong -FORCE parameter.
    
.PARAMETER Name
Specifies the common name used to refer to this Initiator Group. This is commonly the same as the hostname 
of the server. If not specified, the command will default to the hostnme.

.PARAMETER ComputerName
Valid Alias for this argument is also "NodeName" or "CN" or "_SERVER". Specifies the hostname of the Server that the Initiator 
Group is being created for, If left blank, will assume that the command is intending to create and Initiator 
Group for the localhost.

.PARAMETER Description
Specifies a description for this Initiator Group. If not specified, it will first attempt to use the Windows 
description field, if that is NULL it will create a Description of the 
format "Hostname - OS Version - Clustername (if a cluster member)".

.PARAMETER Access_Protocol
Valid Alias for this argument is also "ConnectionType". Used to identify which type of Target device this Initiator 
Group is being made for. If the array only supports a single protocol type, this value will be overridden with the 
correct protocol. Valid values for this argument are "FC" and "iSCSI", but "Fibre Channel" is allowed as it will
be converted to the proper "FC" and ins only included to allow pipelined input to funtion properly with Microsoft
existing Powershell commands.

.INPUTS
You can pipeline the input from numerous commands that output the computername such as Get-ClusterNode. See examples.

.OUTPUTS
Command will return the new Initator Group Object, or if the Initiator Group already exists, will return the existing 
Initiator Group Object. This Initiator Group object can be pipelined to the next stage of a mapping operation which is
to define the individual initiators.

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1,Server2,Server3

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1 -description "A New IGroup for Server123" -access_protocol fc

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1 -description "A New IGroup for Server123" -access_protocol iscsi -target_subnets iscsi-a,iscsi-b

.EXAMPLE
This example will create Initiator Groups for ALL of the members of a Windows Cluster using PowerShell Remoting.
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-ClusterNode | ForEach-Object { Get-ClusterNode $_.NodeName | New-NimInitiatorGroup }

.EXAMPLE
C:\PS> New-NimInitiatorGroup -name testnode4 -target_subnets iSCSI-A,management,iscsi-b | format-list *
Detected that this array is iSCSI based
Setting Access to this Array as iscsi
Finding if Existing Initiator Group Exists
iSCSI-A matches Target Subnet iSCSI-A with Target Subnet ID 1a58cccb25ab411db2000000000000000000000004
management matches Target Subnet Management with Target Subnet ID 1a58cccb25ab411db2000000000000000000000003
WARNING: The management Target Subnet does not allow iSCSI communication
iscsi-b matches Target Subnet iSCSI-B with Target Subnet ID 1a58cccb25ab411db2000000000000000000000005
Executing the following command;
New-NSInitiatorGroup -computername testnode4 -access_protocol iscsi

access_protocol  : iscsi
creation_time    : 10/11/2016 7:22:50 PM
description      :
fc_initiators    :
full_name        : testnode4
id               : 0258cccb25ab411db200000000000000000000004d
iscsi_initiators :
last_modified    : 10/11/2016 7:22:50 PM
name             : testnode4
search_name      : testnode4
target_subnets   : 
computername	 : testnode4
#>

function Z_detect-NIMArray
{ # will return true if works, or false if not
	if ( Get-nsArray -ErrorAction SilentlyContinue )
		{ 	$AName=((Get-nsarray).name)
			Write-host "Validating Connectivitity to Array named = $AName"
			$detected=$true
		} else
		{ 	# exit the module if cant connect to array
			write-host "Could not connect to a valid array, Use Connect-NSArray to connect." -erroraction stop
			$detected=$false
		}
	return $detected
}

function Z_detect-NIMArrayProtocol
{ # used to correct the iSCSI or FC setting, Will take in "iscsi | fc | fibre Channel" but will output the detected "iscsi or fc"	
	param
    ( 	[string[]] 
		$ExpectedProtocol
	)
	if ( get-NSFibreChannelPort )
		{ 	write-Verbose "Array has been identified as Fibre Channel."
			if ( $ExpectedProtocol -eq "iscsi")
				{ 	write-warning "The Access Protocol cannot be iSCSI, resetting value for Fibre Channel"
				} else
				{	write-host "Setting Access to this Array as Fibre Channel"
				}
			$detected="fc"
		} else
		{ 	write-Verbose "Array has been identified as iSCSI."
			if ( ($ExpectedProtocol -eq "fc") -or ($ExpectedProtocol -eq "Fibre Channel") )
				{ 	write-warning "The Access Protocol cannot be Fibre Channel, resetting value for iSCSI"
				} else
				{	write-host "Setting Access to this Array as iSCSI"
				}
			$detected="iscsi"
		}
	return $detected
}		   

function Z_test-nimPSRemote
{ # just a simple test to ensure PS Remoting works on the passed hostname
	param
	(	[string]
		$ztesthost
	)
	if ( invoke-command -ComputerName $ztesthost -scriptblock { get-host } -ErrorAction SilentlyContinue )
		{ 	$detected=$true
			write-host "PowerShell Remoting run successfully against host $ztesthost"
	    } else
		{ 	$detected=$false
			write-warning "Connectivity to host named $ztesthost was denied."
		}
	return $detected
}

function Z_get-nimPShostdescription
{ # just a simple description derived from the host using powershell
	param
	(	[string[]]
		$testhost
	)
	$description=""
	# first determine if the Description is set on the target computer
	$wmio = invoke-command -computername $testhost -scriptblock { get-wmiobject -class win32_operatingsystem }
	if ( -not $wmio.description )
		{ 	# if not set, lets set one, namely the Machinename + OS Version + Cluster Name (if exists)
			if ( invoke-command -computername $testhost -scriptblock { get-cluster } )
				{ 	$clustername=" - Clustername:" + $( invoke-command -computername $testhost -scriptblock { $(get-cluster).name } )
				} else
				{ 	$clus = ""
				}
			$description = $testhost + " - " + $wmio.caption + $clustername
			write-warning "No Description Provided or Detected on Host, setting it as $description"
		} else
		{ 	write-verbose "No Description Provided, using the detected computer description $description"
			$description = $wmio.description
		}
	$description=""""+$description+""""
	return $description
}

function Z_discover-NIMInitiatorGroupByValue
{ # This will accept a $name and find the object for the initiator group and return it
	param
	(	[string]
		$testValue,
		
		[string]
		$ValueType
	)
	$detected=""
	$c = $cd = ( (Get-NSInitiatorGroup).count )
	foreach ( $zGroup in get-nsinitiatorgroup ) 
		{ 	# compair my target subnet to each subnet on the array
			start-sleep -m 25
			Write-Progress -activity "Searching Existing Initiator Groups" `
						   -status "Progress:" `
					       -percentcomplete ( ( ($c-(--$cd)) / $c) * 100 ) `
					       -currentoperation $($zgroup.name)
			if ( ( $testvalue -like $(($zgroup.iscsi_initiators).iqn) ) 	-and ( $valuetype -like "iscsi")  )
				{	write-host "Found Match IQN Checking $testvalue against $(($zgroup.iscsi_initiators).iqn)"
					$detected=$zgroup
				}
			if ( ( $testvalue -like $($zgroup.name) ) 					-and ( $valuetype -like "name") )
				{	write-host "Found Match Checking $testvalue against $($zgroup.name)"
					$detected=$zgroup
				}
			if ( ( ( $testvalue -like $($zgroup.fc_initiators).wwpn) ) 	-and ( $valuetype -like "fc") ) 
				{	write-host "Found Match Checking $testvalue against $($zgroup.name)"
					$detected=$zgroup
				}
			if ( ( $testvalue -like $($zgroup.id) ) 	-and ( $valuetype -like "id") )
				{	write-host "Found Match Checking $testvalue against $($zgroup.id)"
					$detected=$zgroup
				}
		}
	Write-Progress 	-activity "Searching Existing Initiator Groups" `
					-status "Progress:" -percentcomplete ( 100 ) 
	return $detected
}

function Z_fix-NIMHostWWPN
{ # fixes the format from windows 200000001523234 to the corrected 20:00:00:00:12:34:45:ab
	param
	(	[string[]]
		$wwpn
	)
	$correcedWWPN=""
	foreach ($colon in 14,12,10,8,6,4,2 ) 
		{ $CorrectedWWPN=$wwpn.insert($colon,":") 
		}
	return $CorrectedWWPN
}

<#
.SYNOPSIS 
Creates a new Initiator Group on the Nimble Array.

.DESCRIPTION
An Initiator Group is used to define access for a specific server to access a set of Nimble Storage Volumes. 
Commonly the name of the Initiator Group will match the hostname of the server and will act as a container for
the Initiator objects specific to this server which can be set using the followup commnd New-NimInitiator. This
command will ONLY create a new Initiator group if the requisite tests pass such as verification that the host 
contains initators which can communicate with the Nimble Array via the appropriate protocol. To override these 
checks, and force the creation of the Initiator Group without these checks, use the commong -FORCE parameter.
    
.PARAMETER Name
Specifies the common name used to refer to this Initiator Group. This is commonly the same as the hostname 
of the server. If not specified, the command will default to the hostnme.

.PARAMETER ComputerName
Valid Alias for this argument is also "NodeName" or "CN". Specifies the hostname of the Server that the Initiator 
Group is being created for, If left blank, will assume that the command is intending to create and Initiator 
Group for the localhost.

.PARAMETER Description
Specifies a description for this Initiator Group. If not specified, it will first attempt to use the Windows 
description field, if that is NULL it will create a Description of the 
format "Hostname - OS Version - Clustername (if a cluster member)".

.PARAMETER Access_Protocol
Valid Alias for this argument is also "ConnectionType". Used to identify which type of Target device this Initiator 
Group is being made for. If the array only supports a single protocol type, this value will be overridden with the 
correct protocol. Valid values for this argument are "FC" and "iSCSI", but "Fibre Channel" is allowed as it will
be converted to the proper "FC" and ins only included to allow pipelined input to funtion properly with Microsoft
existing Powershell commands.

.INPUTS
You can pipeline the input from numerous commands that output the computername such as Get-ClusterNode. See examples.

.OUTPUTS
Command will return the new Initator Group Object, or if the Initiator Group already exists, will return the existing 
Initiator Group Object. This Initiator Group object can be pipelined to the next stage of a mapping operation which is
to define the individual initiators.

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1,Server2,Server3

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1 -description "A New IGroup for Server123" -access_protocol fc

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> New-NimInitiatorGroup -name Server1 -description "A New IGroup for Server123" -access_protocol iscsi -target_subnets iscsi-a,iscsi-b

.EXAMPLE
This example will create Initiator Groups for ALL of the members of a Windows Cluster using PowerShell Remoting.
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-ClusterNode | ForEach-Object { Get-ClusterNode $_.NodeName | New-NimInitiatorGroup }

.EXAMPLE
C:\PS> New-NimInitiatorGroup -name testnode4 -target_subnets iSCSI-A,management,iscsi-b | format-list *
Detected that this array is iSCSI based
Setting Access to this Array as iscsi
Finding if Existing Initiator Group Exists
iSCSI-A matches Target Subnet iSCSI-A with Target Subnet ID 1a58cccb25ab411db2000000000000000000000004
management matches Target Subnet Management with Target Subnet ID 1a58cccb25ab411db2000000000000000000000003
WARNING: The management Target Subnet does not allow iSCSI communication
iscsi-b matches Target Subnet iSCSI-B with Target Subnet ID 1a58cccb25ab411db2000000000000000000000005
Executing the following command;
New-NSInitiatorGroup -computername testnode4 -access_protocol iscsi

access_protocol  : iscsi
creation_time    : 10/11/2016 7:22:50 PM
description      :
fc_initiators    :
full_name        : testnode4
id               : 0258cccb25ab411db200000000000000000000004d
iscsi_initiators :
last_modified    : 10/11/2016 7:22:50 PM
name             : testnode4
search_name      : testnode4
target_subnets   : 
computername	 : testnode4
#>
function New-NimInitiatorGroup
{
	    [cmdletBinding(SupportsShouldProcess=$true)]
  param
    (	[parameter]
		[switch]
		$force,
		
		[parameter ( 	HelpMessage="Enter a Name for your Initiator Group, commonly matches the Hostname")]
		[string] 
		$name="",

		[parameter ( 	ValueFromPipeline=$True,
						ValueFromPipelineByPropertyName,
						HelpMessage="Enter one or More Computer Names seperated by commas." ) ]
		[Alias("Cn", "NodeName", "_SERVER")] # To allow pipelining, since different MS commands calls things by these names
		[string[]]
		$ComputerName="",
		
		[Parameter ( 	HelpMessage="Enter a Description of this host." ) ]
		[string] 
		$description="",

		[Parameter (	ValueFromPipeline=$True,
						ValueFromPipelineByPropertyName,
						HelpMessage="Enter the Protocol Type the host and array both Support." ) ]
		[Alias("ConnectionType")] # To Allow Pipelining, since this is what MS really calls it
		[validateset("iscsi","fc","Fibre Channel")]
		[string]
		$access_protocol="" ,

		[Parameter (	HelpMessage="Enter the collection of Valid Target Subnets if using iSCSI." ) ]
		[string[]]
		$target_subnets=""
	)
	
	write-verbose "START OF New-NIMInitiatorGroup Command"
	write-verbose "--------------------------------------"
	write-verbose "- Force setting = $force"
	write-verbose "- Name setting = $name"
	write-verbose "- ComputerName setting = $computername"
	write-verbose "- Description setting = $description"
	write-verbose "- Access_Protocol setting = $Access_Protocol"
	write-verbose "- Target_Subnets setting = $Target_Subnets"
	write-verbose "--------------------------------------"
	
	$returnarray=[system.array]@() 

	if ( Z_detect-NIMArray ) 													# Detecting the array
		{ 	$access_protocol =  $(Z_detect-NIMArrayProtocol $access_protocol )	# Discover if I can get to the array, and set the protocol type
			write-verbose "-Pass  = access_protocol=$access_protocol"
		}																		# this is where I set the number of iGroups on the array

	if ( (-not $ComputerName) -and (-not $name) ) 								# if I pass no computername OR initiatorgroup name, then assume using local and set both. 
		{ 	$ComputerName = $name = (hostname)									# Set both and write a warning
			write-warning "No Computername was Passed in as a parameter, assuming localhost"
		}

	if ( ( $computername.count -gt 1 ) -and $name )
		{	write-warning "When Multiple Computernames are selected, you cannot also use a name argument. name argument will not be used."
			$name=""
		}

	if ( (-not $conmputername) -and $name )
		{	if ( $( Z_test-nimPSRemote $name )  ) 
				{	$computername = $name
					write-warning "Since Computername was not specified, but name was, testing to see if it is a computername, Setting computername to same as name"
				} else
				{	$computername = (hostname)
					write-warning "Since name was not a computername that I can powershell remote to, assuming that you meant to use the localhost as the computername."
				}
		}
		
	$VTSL="" # Validated Target Subnet List
	foreach( $tsub in $target_subnets )
		{ 	# walk through each Subnet that was sent in via parameter
			write-verbose "Detecting if Target Subnet $tsub exists on Array"
			foreach($dsub in get-nssubnet)
				{	# compair my target subnet to each subnet on the array
					if ( $tsub -eq $dsub.name ) # These compairs are already case insensitive
						{ 	# What to do when a parameter subnet matches an array subnet
							$outmsg=$tsub+" matches Target Subnet "+$dsub.name+" with Target Subnet ID "+$dsub.id
							write-verbose "$tsub matches Target Subnet $($dsub.name) with Target Subnet ID $($dsub.id)"
							if ( $dsub.allow_iscsi )
								{ 	write-verbose "This subnet to authorized for $tsub Target Subnet"
									if ( $VTSL )
										{ 	$VTSL+="," + $dsub.name
										} else
										{ 	$VTSL=$dsub.name
										}
								} else
								{ 	write-warning "The $tsub Target Subnet does not allow iSCSI communication"
								}
						} else
						{	write-verbose "No match checking Target Subnet $tsub against Target Subnet $($dsub.name)"
						}
				}	
		}
	if ( $VTSL )
		{ 	write-verbose "this is the cleansed list $VTSL"
			$target_subnets=$VTSL
		} else
		{	write-verbose "The list of Target Subnets = *"
			$target_subnets="*"
		}
	
	write-verbose "Number of items in Computername = $($computername.count)"
	foreach ( $Computer in $ComputerName )
		{ 	if ( ( -not $name) -or ( $($computername.count) -gt 1 ) ) # if the group name is blank, this will default it to the computer name 
				{	$name = $Computer
					write-warning "Hostname was left blank, settings it same as the Computer=$Computer or multiple computernames selected"	
				} 
			if ( $name -and ( $($conmputername.count) -eq 1 ) )
				{	# a name was set, as well as a computername, so we must want to use a non-standard name
					write-warning "The Computename and the Hostname differ, this is non-standard, and you must use FORCE"
					if ( $force )
						{ 	write-warning "The Computername and the Hostname differ, but option is being forced"
						} else
						{ 	$skipall=$true
							write-error "The Computename and the Hostname differ, this is non-standard, and you must use FORCE"
						}	
				}
			$skipall = ( $force ) -or (-not $( Z_test-nimPSRemote $computer ) ) # if I cant connect to the host to validate, then dont make the igroup unless forced
			# detect if this servers initiator group already exists
			$alreadyExists=$false
			write-verbose "Detected $C Initiator Groups on the Array, Checking them now"
			if ( $( Z_discover-NIMInitiatorGroupByValue $name "name" ) )
				{ 	$alreadyExists=$true
				}
			# This is a initiator group for the servers, validate it has those type of HBAs
			write-verbose "This command is being asked to create an iGroup for server $Computer"
			if ($access_protocol -like "iscsi")
				{	# Must be iSCSI, Checking if iSCSI service is runningif
					if ( (invoke-command -computername $computer -scriptblock {get-initiatorport | where {$_.connectiontype -like "iscsi" } } ) )
						{ 	Write-verbose "The server has an iSCSI Initiator configured"
						} else
						{ 	Write-warning "The server has NO iscsi Initiator configured"
							if ( -not $force) 
								{	$skipall=$true
								}
						}
				} else
				{ 	# Must be FC, Checking if FC ports exist on this server 
					if ( (invoke-command -computername $computer -scriptblock {get-initiatorport | where {$_.connectiontype -like "Fibre Channel"} } ) )
						{ 	write-host "The server has an FC Initiator configured"
						} else
						{ 	Write-warning "The server has NO FC Initiator configured"
							if ( -not $force) 
								{	$skipall=$true
								}
						}
				}
			if ( -not $description )
				{ 	$descrition = $( Z_get-nimPShostdescription $computer )
					write-verbose "Description for host $computer = $description"
				}
				
			$description=""""+$description+""""
			$target_subnets=""""+$target_subnets+"""" 
			if ( $alreadyexists )
				{ 	write-error "This Initiator Group Already Exists. Array will not be modified. To modify this group, use Set-NIMInitiatorGroup"
				} else
				{ 	if ( $PSCmdlet.ShouldProcess('Issuing Command to Create Initiator Group') -and ( -not ($skipall) ) )
						{ 	# The Creation command goes here.
							write-host "Executing the following command;"
							write-host "New-NSInitiatorGroup -name $name -access_protocol $access_protocol -description $description"
							$r=New-NSInitiatorGroup -name $name -access_protocol $access_protocol -description $description
						} else
						{ 	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
							write-warning "This is the what-if or Initiator group failed required criteria: following command would be executed;"
							write-warning "New-NSInitiatorGroup -name $name -access_protocol $access_protocol -description $description"		
						}
				}	
			# This will return as the object the initiator group it just created, or if it already exists, the current one.
			if ( $r = $( Z_discover-NIMInitiatorGroupByValue $name "name"  ) )
				{	# reset all the variables if multiple servers were selected.
				 	$r | add-member -type NoteProperty -name ComputerName -value $computer
					$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
					$returnarray+=$r
				}
			$alreadyExists=$false
			$skipall=$false
			$description=""
		} # End for loop
	$returnarray.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
	write-verbose "--------------------------------------"
	write-verbose "- Force setting = $force"
	write-verbose "- Name setting = $name"
	write-verbose "- ComputerName setting = $computername"
	write-verbose "- Description setting = $description"
	write-verbose "- Access_Protocol setting = $Access_Protocol"
	write-verbose "- Target_Subnets setting = $Target_Subnets"
	write-verbose "--------------------------------------"
	write-verbose "END OF New-NIMInitiatorGroup Command"
	return $returnarray
} # end the function
export-modulemember -function New-NimInitiatorGroup

<#
.SYNOPSIS 
Retrieves the Initiator Group or collection of Initiator groups on the Nimble Array.

.DESCRIPTION
An Initiator Group is used to define access for a specific server to access a set of Nimble Storage Volumes. 
Commonly the name of the Initiator Group will match the hostname of the server and will act as a container for
the Initiator objects specific to this server which can be set using the followup commnd New-NimInitiator. This
command will ONLY find existing Initiator group and return them. By using no arguments, the command will return
the entire set of initiator groups, however, you can choose to use the parameters supplied to only retrieve the 
relavent initiator groups. Since this command will not modify the array or hosts in any way, the WhatIf, Confirm,
and Force options are not implemented.
    
.PARAMETER Name
Specifies the common name used to refer to this Initiator Group. This is commonly the same as the hostname 
of the server. If not specified, the command will default to all. This can be a single name or a list of names
seperated by commas

.PARAMETER ComputerName
Valid Alias for this argument is also "NodeName" or "CN" or "_SERVER". This can be a single computer name or a collection of 
computer names seperated by commas. Specifies the hostname of the Server that the Initiator Group is being serched for. 
This is verified by using PowerShell Remoting to retrieve the IQN or WWPNs of the server and checking
the membership against each Initiator Group on the array.

.PARAMETER id
Specifies the array ID used to reference the Initiator Group. This can be a single ID, or a list of IDs seperated
by commas. 

.INPUTS
You can pipeline the input from numerous commands that output the computername such as Get-ClusterNode. See examples.

.OUTPUTS
Command will return the Initator Group Object(s). This Initiator Group object can be pipelined to the next stage 
of a mapping operation which is to define the individual initiators using the new-NimInitiator command.

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-NimInitiatorGroup
Validating Connectivitity to Array named = mcs460gx2
Gathering All Initiator Groups
Found correct Initiator Group, $iqn matches $(($igroup.iscsi_initiators).iqn)
WWPN number $hbacount found =  $wwpni in IGroup named $($igroup.name)
name             id                                         access_protocol computerName description       
----             --                                         --------------- ------------ -----------       
sql-p            0247a5f2220a9575e0000000000000000000000027 iscsi                        My Production Sql Server                  
sql-c            0247a5f2220a9575e0000000000000000000000034 iscsi     					 My Dev Sql Server
Oracle-p         0247a5f2220a9575e0000000000000000000000037 iscsi                        My Production Oracle Server                 
Oracle-c         0247a5f2220a9575e0000000000000000000000044 iscsi     					 My Dev Oracle Server

.EXAMPLE
This example will reteive ALL initiator Groups from the array.
C:\PS> Get-NimInitiatorGroup

.EXAMPLE
This example will Retrieve only the Initiators from the array that match the given Initiator Group Names.
C:\PS> Get-NimInitiatorGroup -name Server1,Server2,Server3

.EXAMPLE
This example will return and initiator with a name of Server1 and additionally the specified id.
C:\PS> Get-NimInitiatorGroup -name Server1 id 1a58cccb25ab411db2000000000000000000000004

.EXAMPLE
This example will create Initiator Groups for ALL of the members of a Windows Cluster using PowerShell Remoting.
C:\PS> Get-ClusterNode | ForEach-Object { Get-ClusterNode $_.NodeName | Get-NimInitiatorGroup }

.EXAMPLE
This example will return any initiator group that matches of the given criteria, note, this may refer to a single initiator group, or three seperate initiator groups.
PS:> Get-NimInitiatorGroup -name sql-p,node2 -id 0247A5f2220A9575E0000000000000000000000034 -Computername Server1
Validating Connectivitity to Array named = mc480gx2
The server Server1 has an FC Initiator configured
WWPN number 1 found =  20:00:00:00:55:44:23:11 in IGroup named Server1
WWPN number 2 found =  20:00:00:00:55:4a:cc:12 in IGroup named Server1
The number of Initiators matches the number of WWPN in the Initiator Group Server1
Found correct Initiator Group, sql-p matches sql-p
Found correct Initiator Group, 0247A5f2220A9575E0000000000000000000000034 matches 0247a5f2220a9575e0000000000000000000000034
WARNING: Initiator group that matches name node2 was not found

name                       id                                         access_protocol computerName        description       
----                       --                                         --------------- ------------        -----------       
sql-p                      0247a5f2220a9575e0000000000000000000000027 fc                                                              
sql-c                      0247a5f2220a9575e0000000000000000000000034 fc                   
Server1                    0247a5f2220a9575e0000000000000000000000034 fc	           Server1            Windows 2016 Server
#>
function Get-NimInitiatorGroup
{
		[cmdletBinding()]
	param
		(	[parameter ( 	ValueFromPipeline=$True,
							ValueFromPipelineByPropertyName,
							HelpMessage="Enter a one or more Names seperated by commas.")]
			[Alias("Cn", "NodeName", "_SERVER")] 
			[string[]] 
			$ComputerName="",
		
			[parameter ( 	ValueFromPipeline=$True,
							ValueFromPipelineByPropertyName,
							HelpMessage="Enter a one or more Names seperated by commas.")]
			[string[]] 
			$name="",

			[parameter ( 	HelpMessage="Enter a one or more Initiator Groups.")]
			[string] 
			$id=""
		)
	
	$returnarray=[system.array]@()

if ( Z_detect-NIMArray )
	{ 	$access_protocol= $(Z_detect-NIMArrayProtocol $access_protocol )
	}
	
if ( -not $ComputerName ) 
	{ 	write-verbose "No Computername was Given"
	} else 
	{ 	foreach ( $Computer in $ComputerName )
			{ 	$foundname=$false
				if ( Z_test-nimPSRemote $computer ) 
					{ 	write-host "PowerShell Remoting run successfully against remote host $Computer"
						if ($access_protocol -like "iscsi")
							{ 	# Must be iSCSI, Checking if iSCSI service is runningif
								if ( $IQN=$(invoke-command -computername $computer -scriptblock { $( get-initiatorport | where {$_.connectiontype -like "iscsi"} ).nodeaddress }) ) 
									{ 	write-host "The server has an iSCSI Initiator configured"
										$cd=$c # countdown = count
										write-verbose "Detected $Counter Initiator Groups on the Array, Checking them now"
										$foundname=$true
										$igroupname=$(Z_discover-NIMInitiatorGroupByValue $IQN "iscsi").name
										if ( $r = Z_discover-NIMInitiatorGroupByValue $IQN "iscsi"  )
											{	$r | add-member -type NoteProperty -name ComputerName -value $computer
												$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
												$returnarray+=$r
											} else
											{	Write-warning "Initiator group that matches name the IQN used by $computer was not found"
											}
									} else
									{ 	write-host "This server contains no iSCSI IQN"
									}
							}
						if ( $access_protocol -like "fc")
							{	# Must be FC, Checking if FC ports exist on this server 
								if ( $wwpn=$(invoke-command -computername $computer -scriptblock { $( get-initiatorport | where {$_.connectiontype -like "Fibre Channel"} ).portaddress }) )
									{ 	 $hbacount=0
										foreach ($wwpni in $wwpn)
										{ 	$wwn=$( Z_fix-NIMHostWWPN $wwpni )							  
											if ( $r = Z_discover-NIMInitiatorGroupByValue $wwn "fc" )
												{	$r | add-member -type NoteProperty -name ComputerName -value $computer
													$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
													$returnarray+=$r
													$foundname=$true
													$hbacount=$hbacount+1
												} else
												{	Write-warning "Initiator group that matches name the IQN used by $computer was not found"
												}
										}
										if ( $hbacount -ne $($wwpn.count) )
											{	Write-warning "This Initiator Group only contains one initiator, best practice dictates two HBAs"
											}
									}
							}
						if ( (-not $foundname) -and ( $r = Z_discover-NIMInitiatorGroupByValue $Computer "name"  ) )
							{	$r | add-member -type NoteProperty -name ComputerName -value $computer
								$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
								$returnarray+=$r
								write-warning "The initiator group named $computer was not found via WWPN or IQN lookup, but found via simple name to computer name match."
								write-warning "This may be indicative of an initiator group that doesnt contain the correct WWPN or IQN."
							} else
							{	write-warning "The initiator group for computer $computer was not found via WWPN or IQN or simple name match."
							}
					} else
					{	write-warning "Cannot connect via PowerShell Remoting to Server $computer to find the initiator group using the WWPN or the IQN"
						write-warning "Will attempt to return any Initiator Group with name matching without validating the IQN or WWPN"
						if ( $r = Z_discover-NIMInitiatorGroupByValue $Computer "name"  )
							{	$r | add-member -type NoteProperty -name ComputerName -value $computer
								$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
								$returnarray+=$r
							} else
							{	write-warning "The initiator group for computer $computer was not found via WWPN or IQN or simple name match. PowerShell Remoting did not work."
							}
					}
			}
	}
	
if ( -not $name)
	{ 	Write-verbose "No Name variable was given." 
	} else
	{ 	write-verbose "Name Argument Passed in is $name"
		foreach ( $n in $name )
			{	if ( $r = Z_discover-NIMInitiatorGroupByValue $n "name"  )
					{	# $r | add-member -type NoteProperty -name ComputerName -value $computer
						$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
						$returnarray+=$r
					} else
					{	write-warning "The initiator group named $n was not found"
					}
			}
    }

if ( -not $id)
	{ # then 
	  Write-Verbose "No Id's were give to search for."
	} else
	{ foreach ( $idd in $id )
		{	if ( $r = Z_discover-NIMInitiatorGroupByValue $IDD "id"  )
				{	$r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	
					$returnarray+=$r
				} else
				{	write-warning "The initiator group with ID $idd was not found"
				}
		}
	}

if ( -not $name -and -not $id -and -not $ComputerName)
	{ 	# They must want Everything 
		write-host "Gathering All Initiator Groups"
		$cd=$c=(get-nsinitiatorgroup).count # countdown=counter
        write-verbose "Detected $Counter Initiator Groups on the Array, Checking them now"
		# $returnarray=$(get-nsinitiatorgroup)
			foreach ( $igroup in get-NSInitiatorgroup )
			{ $r=$igroup
			  start-sleep -m 25
			  Write-Progress -activity "Gathering Existing Initiator Groups" `
							 -status "Progress:" `
							 -percentcomplete ( ($c-(--$cd)) / $c * 100 ) `
							 -currentoperation $($igroup.name)
	          $r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
			  $returnarray+=$r			  
			}
			Write-Progress -activity "Gathering Finished for Initiator Groups" -status "Progress:" -percentcomplete ( 100 )
	}
		
$returnarray.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
return $returnarray
}
export-modulemember -function Get-NimInitiatorGroup 	

<#
.SYNOPSIS 
Allow the modification of existing an Initiator Group or collection of Initiator groups on the Nimble Array.

.DESCRIPTION
An Initiator Group is used to define access for a specific server to access a set of Nimble Storage Volumes. 
Commonly the name of the Initiator Group will match the hostname of the server and will act as a container for
the Initiator objects specific to this server which can be set using the followup commnd New-NimInitiator. This
command will ONLY find existing Initiator group(s) allow the update of the description or the name of the 
Initiator group. By using no arguments, the command will assume you expect to update the initiator group that 
matches the existing host only the entire set of initiator groups. 
If the Initiator group contains no description the command will attempt to generate a proper description 
automatically. If the host contains a self-description in the host, this self-description will be used over the 
default "OSVersion-Hostname-Clustername" that is generated otherwise.
    
.PARAMETER Name
Specifies the common name(s) used to refer to this Initiator Group. This is commonly the same as the hostname 
of the server. . This can be a single name or a list of names seperated by commas. If multple names are 
selected, the description can only be an autogenerated description, and the computername must match the 
initiator group name.

.PARAMETER ComputerName
Valid Alias for this argument is also "NodeName" or "CN" or "_SERVER". This can be a single computer name 
or a collection of computer names seperated by commas. Specifies the hostname of the Server that the Initiator 
Group is being serched for.  This is verified by using PowerShell Remoting to retrieve the IQN or WWPNs 
of the server to ensure the correct initiator group names. 

.PARAMETER id
Specifies the array ID used to reference the Initiator Group. This can be a single ID, or a list of IDs seperated
by commas. This value can be used to identify the correct initiator group, but is not changable.

.PARAMETER force 
When using the -name argument, this will allow you to force a specific -description to be set for an initiator group. 
The default behavior is to only add a description when no previous description exists.
If the initiator group is found using the -computername argument, this will allow you to change the name of the 
initiator group from its current name to the same name as the computername for the server.

.INPUTS
You can pipeline the input from numerous commands that output the computername such as Get-ClusterNode. See examples.

.OUTPUTS
Command will return the Initator Group Object(s). This Initiator Group object can be pipelined to the next stage 
of a mapping operation which is to define the individual initiators using the new-NimInitiator command.

.EXAMPLE
C:\PS> set-NimInitiatorGroup
Validating Connectivitity to Array named = mcs460gx2
WARNING: No Computername or Initiator Group name was Passed in as a parameter, assuming you want to modify ONLY this host sql-p.
WARNING: No description was given, if description is not set this command will use an autogenerated description
Gathering All Initiator Groups
Found correct Initiator Group, 0247A5f2220A9575E0000000000000000000000034 matches 0247a5f2220a9575e0000000000000000000000034

name             id                                         access_protocol computerName description       
----             --                                         --------------- ------------ -----------       
sql-p            0247a5f2220a9575e0000000000000000000000027 iscsi                        OS:Windows2012r2 - Hostname:sql-p - Clustername:SQLClus                   

.EXAMPLE
In this example, the computername and the initiator group name do not match, but since I am using force, 
it will reset the initiatorgroup name to match the computername. 
C:\PS> set-NimInitiatorGroup -force $true -computername sql-dev
Validating Connectivitity to Array named = mcs460gx2
WARNING: No Computername or Initiator Group name was Passed in as a parameter, assuming you want to modify ONLY this host sql-p.
WARNING: No description was given, if description is not set this command will use an autogenerated description
Gathering All Initiator Groups
Found correct Initiator Group, 0247A5f2220A9575E0000000000000000000000034 matches 0247a5f2220a9575e0000000000000000000000034
The Initiator Group sql-d does not match sql-dev
name             id                                         access_protocol computerName description       
----             --                                         --------------- ------------ -----------       
sql-dev            0247a5f2220a9575e0000000000000000000000027 iscsi                        OS:Windows2012r2 - Hostname:sql-p - Clustername:SQLClus

.EXAMPLE
This example will reset only the Initiators from the array that match the given Initiator Group Names.
If the initiatornames match the computernames, it will attempt to retreive the default descriptions of each
host and apply it to each initiator group, but only if the existing descriptions do not exist.
C:\PS> Get-NimInitiatorGroup -name Server1,Server2,Server3

.EXAMPLE
This example will attempt to update both initiator groups with a name of Server1 and additionally the specified id.
In each case, if the descriptions are blank on the array, the command will update the descriptions to match detected values
C:\PS> Get-NimInitiatorGroup -name Server1 id 1a58cccb25ab411db2000000000000000000000004

.EXAMPLE
This example will update Initiator Groups for ALL of the members of a Windows Cluster using PowerShell Remoting. It will force all
of the initiator groups to have the same description, but will also match sure that the initiator group names match the hostnames
C:\PS> Get-ClusterNode | ForEach-Object { Get-ClusterNode $_.NodeName | set-NimInitiatorGroup -description "A Member of the Cluster:Clustername" -force $true}

#>	
function Set-NimInitiatorGroup
{
	    [cmdletBinding(SupportsShouldProcess=$true)]
  param
    (	[parameter]
		[switch]
		$force,

		[parameter ( 	HelpMessage="Enter the Name of the Initiator Group, commonly matches the Hostname")]
		[string] 
		$name="",

		[parameter ( 	ValueFromPipeline=$True,
						ValueFromPipelineByPropertyName,
						HelpMessage="Enter one or More Computer Names seperated by commas." ) ]
		[Alias("Cn", "NodeName", "_SERVER")] # To allow pipelining, since different MS commands calls things by these names
		[string[]]
		$ComputerName="",

		[Parameter ( 	HelpMessage="Enter a Description of this host." ) ]
		[string] 
		$description="",

		[Parameter (	HelpMessage="Enter the collection of Valid Target Subnets if using iSCSI." ) ]
		[string[]] $target_subnets=""
	)

if ( -not $ComputerName -and -not $name ) 
	{ # initial condituon that we must populate at least the localhost
	  $ComputerName = (hostname) 
	  write-warning "No Computername or Initiator Group name was Passed in as a parameter, assuming you want to modify ONLY this host $Computername."
	}

if ( -not $description)
	{ # just a warning that we will use autodefined
	  write-warning "No description was given, if description is not set this command will use an autogenerated description"
	}
	
if ( Z_detect-NIMArray )
	{ 	$access_protocol= $(Z_detect-NIMArrayProtocol $access_protocol )
	} 

$VTSL="" # Validated Target Subnet List
foreach( $tsub in $target_subnets )
	{ 	# walk through each Subnet that was sent in via parameter
		write-verbose "Detecting if Target Subnet $tsub exists on Array"
		foreach($dsub in get-nssubnet)
			{	# compair my target subnet to each subnet on the array
				if ( $tsub -eq $dsub.name ) # These compairs are already case insensitive
					{ 	# What to do when a parameter subnet matches an array subnet
						$outmsg=$tsub+" matches Target Subnet "+$dsub.name+" with Target Subnet ID "+$dsub.id
						write-host $outmsg
						if ( $dsub.allow_iscsi )
							{ 	write-verbose "This subnet to authorized for $tsub Target Subnet"
								if ( $VTSL )
									{ 	$VTSL+="," + $dsub.name
									} else
									{ 	$VTSL=$dsub.name
									}
							} else
							{ 	write-warning "The $tsub Target Subnet does not allow iSCSI communication"
							}
					} else
					{ 	write-verbose "No match checking Target Subnet $tsub against Target Subnet $($dsub.name)"
					}
			}	
	}
write-verbose "this is the cleansed list $VTSL versus the original list $target_subnets"
if ( $VTSL )
	{ 	write-verbose "this is the cleansed list $VTSL"
		$target_subnets=$VTSL
	} else
	{ 	write-verbose "The list of Target Subnets = *"
		$target_subnets="*"
	}	
$target_subnets=""""+$target_subnets+"""" 
write-verbose "The Cleansed list of Subnets is $target_subnets"   

$returnarray=[system.array]@()
write-verbose "-Pass Values of the variables equal the following;"
write-verbose "-Pass  = Computername=$Computername"
write-verbose "-Pass  = name=$name"
write-verbose "-Pass  = description=$description"
write-verbose "-Pass  = target_subnets=$target_subnets"
write-verbose "-Pass  = -Force =$force"
if ( (-not $computername) -and (-not $name) )
	{	$computername = (hostname) 	
	}

if ( -not $ComputerName ) 
	{ 	write-verbose "No Computername was Given"
	} else 
	{ 	write-debug "Number of items in Computername = $($computername.count)"
		foreach ( $Computer in $ComputerName )
			{ 	if ( $z=get-NimInitiatorGroup -Computername $Computer )
					{ 	Write-host "Found Initiator Group for $computer"
						if ( -not $z.description -or $force)
							{ 	if ( -not $z.description )
									{ 	write-host "No Description exists on the array for this Initiator Group"
									} else
									{ 	write-warning "A Description exists however the Force option was used, so it will be overwritten"
									}
								if ( $description)
									{ 	write-host "A Description was given, and no existing description currently exists."
										write-host "Updating the Initiator Group." 
									} else 
									{ $description = $(z_get-nimPShostdescription $computer )
									}
							}
						$description=""""+$description+""""
						if ( $PSCmdlet.ShouldProcess('Issuing Command to Modify Initiator Group') )
							{ 	# The modify command goes here.
								write-host "Executing the following command;"
								write-host "Set-NSInitiatorGroup id $($z.id) -description $description"
								$y=set-nsinitiatorgroup -id $($z.id) -description $description
								if ( ($z.name -ne $computer) -and $force )
									{	write-warning "Computer name and Initiator Group name differ, since force option was used initiator group will be renamed."
										$y=set-nsinitiatorgroup -id $($z.id) -name $computer
									}
								$y | add-member -type NoteProperty -name ComputerName -value $computer
								$y.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
								$returnarray+=$y
							} else
							{	 # since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
								write-warning "This is the what-if: following command would be executed;"
								write-warning "set-nsinitiatorgroup -id $($z.id) -description $description"		
							}
					} else
					{ 	write-error "An Initiator Group that matches $Computer was not found"
					}
			}
	}

if ( -not $Name )
	{ 	write-host "No Initiator Group Names were given"
	} else
	{	foreach ( $nam in $Name )
			{	# detect if this servers initiator group already exists
				write-host "Finding if Existing Initiator Group Exists"
				if ( $z=get-niminitiatorgroup -name $nam )
					{ 	if ($access_protocol -like "iscsi")
							{	# Must be iSCSI, Checking if iSCSI service is runningif
								if ( (invoke-command -computername $nam -scriptblock {get-initiatorport} | where {$_.connectiontype -like "iscsi"}) )
									{	write-host "The server has an iSCSI Initiator configured"
									} else
									{ 	Write-warning "The server has NO iscsi Initiator configured"
									}
							} else
							{ 	# Must be FC, Checking if FC ports exist on this server 
								if ( (invoke-command -computername $nam -scriptblock {get-initiatorport} | where {$_.connectiontype -like "Fibre Channel"} ) )
									{ 	write-host "The server has an FC Initiator configured"
									} else
									{	Write-warning "The server has NO FC Initiator configured"
									}
							}
						if ( $description)
									{ 	write-host "A Description was given, and no existing description currently exists."
										write-host "Updating the Initiator Group." 
									} else 
									{ $description = $(z_get-nimPShostdescription $nam )
									}
						if ( $PSCmdlet.ShouldProcess('Issuing Command to Modify Initiator Group') )
							{ 	# The modify command goes here.
								write-host "Executing the following command;"
								write-host "Set-NSInitiatorGroup -id $($z.id) -description $description"
								$y=set-nsinitiatorgroup -id $($z.id) -description $description
								$y | add-member -type NoteProperty -name ComputerName -value $computer
								$y.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
								$returnarray+=$y
							} else
							{	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
								write-warning "This is the what-if: following command would be executed;"
								write-warning "set-nsinitiatorgroup -id $($z.id) -description $description"		
							}
					} else
					{ 	write-error "An Initiator Group that matches $nam was not found"
					}
			}
	}

$returnarray.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
return $returnarray
} # end the function
export-modulemember -function Set-NimInitiatorGroup

<#
.SYNOPSIS 
Allow the Removal of existing an Initiator Group or collection of Initiator groups on the Nimble Array.
    
.PARAMETER Name
Specifies the common name(s) used to refer to this Initiator Group. This is commonly the same as the hostname 
of the server. . This can be a single name or a list of names seperated by commas. If multple names are 
selected, the description can only be an autogenerated description, and the computername must match the 
initiator group name.

.PARAMETER ComputerName
Valid Alias for this argument is also "NodeName" or "CN" or "_SERVER". This can be a single computer name 
or a collection of computer names seperated by commas. Specifies the hostname of the Server that the Initiator 
Group is being serched for.  This is verified by using PowerShell Remoting to retrieve the IQN or WWPNs 
of the server to ensure the correct initiator group names. 

.PARAMETER id
Specifies the array ID used to reference the Initiator Group. This can be a single ID, or a list of IDs seperated
by commas. This value can be used to identify the correct initiator group, but is not changable.

.INPUTS
You can pipeline the input from numerous commands that output the computername such as Get-ClusterNode. See examples.

.OUTPUTS
Command will return the Initator Group Object(s). This Initiator Group object can be pipelined to the next stage 
of a mapping operation which is to define the individual initiators using the new-NimInitiator command.

.EXAMPLE
C:\PS> remove-NimInitiatorGroup
Validating Connectivitity to Array named = mcs460gx2
WARNING: No Computername or Initiator Group name or ID(s) was Passed in as a parameter, This command will do nothing.                   

.EXAMPLE
In this example, the computername and the initiator group name do not match, but since I am using force, 
it will reset the initiatorgroup name to match the computername. 
C:\PS> remove-NimInitiatorGroup -computername sql-dev
Validating Connectivitity to Array named = mcs460gx2

name             id                                         access_protocol computerName description       
----             --                                         --------------- ------------ -----------       
sql-dev            0247a5f2220a9575e0000000000000000000000027 iscsi                        OS:Windows2012r2 - Hostname:sql-p - Clustername:SQLClus

.EXAMPLE
This example will reset only the Initiators from the array that match the given Initiator Group Names.
If the initiatornames match the computernames, it will attempt to retreive the default descriptions of each
host and apply it to each initiator group, but only if the existing descriptions do not exist.
C:\PS> remove-NimInitiatorGroup -name Server1,Server2,Server3

.EXAMPLE
This example will attempt to update both initiator groups with a name of Server1 and additionally the specified id.
In each case, if the descriptions are blank on the array, the command will update the descriptions to match detected values
C:\PS> remove-NimInitiatorGroup -id 1a58cccb25ab411db2000000000000000000000004

.EXAMPLE
This example will remove Initiator Groups for ALL of the members of a Windows Cluster using PowerShell Remoting. It will force all
of the initiator groups to have the same description, but will also match sure that the initiator group names match the hostnames
C:\PS> Get-ClusterNode | ForEach-Object { Get-ClusterNode $_.NodeName | remove-NimInitiatorGroup }

#>	
function Remove-NimInitiatorGroup
{
	    [cmdletBinding(SupportsShouldProcess=$true)]
  param
    (	[parameter ( 	HelpMessage="Enter the Name of the Initiator Group, commonly matches the Hostname")]
		[string[]] 
		$name="",

		[parameter ( 	ValueFromPipeline=$True,
						ValueFromPipelineByPropertyName,
						HelpMessage="Enter one or More Computer Names seperated by commas." ) ]
		[Alias("Cn", "NodeName", "_SERVER")] # To allow pipelining, since different MS commands calls things by these names
		[string[]]
		$ComputerName="",
		
		[parameter ( 	HelpMessage="Enter the ID of the Initiator Group.")]
		[string[]] 
		$id=""
	)

if ( -not $ComputerName -and -not $name -and -not $id ) 
	{ # initial condituon that we must populate at least the localhost
	  write-warning "No Computername or Initiator Group name or ID(s) was Passed in as a parameter, This command will do nothing."
	}
	
if ( Z_detect-NIMArray )
	{ 	$access_protocol= $(Z_detect-NIMArrayProtocol $access_protocol )
	}    

$returnarray=[system.array]@()
write-verbose "-Pass Values of the variables equal the following;"
write-verbose "-Pass  = Computername=$Computername"
write-verbose "-Pass  = name=$name"
write-verbose "-Pass  = description=$description"
write-verbose "-Pass  = target_subnets=$target_subnets"
write-verbose "-Pass  = -Force =$force"

if ( -not $ComputerName ) 
	{ 	write-verbose "No Computername was Given"
	} else 
	{ 	write-debug "Number of items in Computername = $($computername.count)"
		foreach ( $Computer in $ComputerName )
			{ 	if ( $z=get-NimInitiatorGroup -Computername $Computer )
					{ 	Write-host "Found Initiator Group for $computer"
						if ( $PSCmdlet.ShouldProcess('Issuing Command to Modify Initiator Group') )
							{ 	# The modify command goes here.
								write-host "Executing the following command;"
								write-host "remove-NSInitiatorGroup id $($z.id)"
								$y=remove-nsinitiatorgroup -id $($z.id)
								$y | add-member -type NoteProperty -name ComputerName -value $computer
								$y.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
								$returnarray+=$y
							} else
							{	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
								write-warning "This is the what-if: following command would be executed;"
								write-warning "remove-nsinitiatorgroup -id $($z.id)"		
							}
					} else
					{ 	write-error "An Initiator Group that matches $Computer was not found"
					}
			}
	}

if ( -not $Name )
	{ 	write-host "No Initiator Group Names were given"
	} else
	{	foreach ( $nam in $Name )
			{	# detect if this servers initiator group already exists
				write-host "Finding if Existing Initiator Group Exists"
				if ( $z=get-niminitiatorgroup -name $nam )
					{ 	if ( $PSCmdlet.ShouldProcess('Issuing Command to Modify Initiator Group') )
							{ 	# The modify command goes here.
								write-host "Executing the following command;"
								write-host "Remove-NSInitiatorGroup -id $($z.id)"
								$y=set-nsinitiatorgroup -id $($z.id)
								$y | add-member -type NoteProperty -name ComputerName -value $computer
								$y.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
								$returnarray+=$y
							} else
							{	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
								write-warning "This is the what-if: following command would be executed;"
								write-warning "Remove-nsinitiatorgroup -id $($z.id)"
							}
					} else
					{ 	write-error "An Initiator Group that matches $nam was not found"
					}
			}
	}

if ( -not $id )
	{ 	write-host "No Initiator Group IDs were given"
	} else
	{	foreach ( $idd in $id )
			{	# detect if this servers initiator group already exists
				write-host "Finding if Existing Initiator Group Exists"
				if ( $z=get-niminitiatorgroup -id $idd )
					{ 	if ( $PSCmdlet.ShouldProcess('Issuing Command to Modify Initiator Group') )
							{ 	# The modify command goes here.
								write-host "Executing the following command;"
								write-host "Remove-NSInitiatorGroup -id $($z.id)"
								$y=set-nsinitiatorgroup -id $($z.id)
								$y | add-member -type NoteProperty -name ComputerName -value $computer
								$y.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
								$returnarray+=$y
							} else
							{	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
								write-warning "This is the what-if: following command would be executed;"
								write-warning "Remove-nsinitiatorgroup -id $($z.id)"
							}
					} else
					{ 	write-error "An Initiator Group that matches $nam was not found"
					}
			}
	}
$returnarray.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
return $returnarray
} # end the function
export-modulemember -function Remove-NimInitiatorGroup

function New-NimInitiator
{
	    [cmdletBinding(SupportsShouldProcess=$true)]
  param
    (	[parameter]
		[switch]
		$force,

		[parameter ( 	mandatory=$false,
						ValueFromPipelineByPropertyName=$True	)]
		[Alias("id")]
		[string] 
		$initiator_group_id="",

		[parameter ( 	mandatory=$false,
						ValueFromPipelineByPropertyName=$True,
						HelpMessage="Enter a Name for your Initiator Group, commonly matches the Hostname")]
		[Alias("name")]
		[string] 
		$initator_group_name="",

		[parameter ( 	mandatory=$false,
						HelpMessage="Enter a Name for your Initiator.")]
		[string] 
		$label="",

		[parameter ( 	mandatory=$false,
						ValueFromPipelineByPropertyName=$True )	 ]
		[Alias("Cn", "NodeName", "_SERVER")] # To allow pipelining, since different MS commands calls things by these names
		[string]
		$ComputerName="",

		[Parameter ( 	mandatory=$false,
						HelpMessage="Enter a Description of this individual initiator." ) ]
		[string] 
		$alias="",

		[Parameter (	mandatory=$false,
						HelpMessage="Enter the Protocol Type the host and array both Support." ) ]
		[Alias("ConnectionType")] # To Allow Pipelining, since this is what MS really calls it
		[validateset("iscsi","fc","Fibre Channel")]
		[string]
		$access_protocol="" ,

		[Parameter (	mandatory=$false,
						HelpMessage="Enter the IQN for the iSCSI Adapter." ) ]
		[string]
		$iqn="",
		
		[Parameter (	mandatory=$false,
						HelpMessage="Enter the single or collection of Valid WWPNs in format including Colons" ) ]
		[string[]]
		$wwpn="",
		
		[Parameter (	mandatory=$false,
						HelpMessage="Enter the single or collection of Valid WWPNs in format including Colons" ) ]
		[string[]]
		$IP_Address="""*"""
	)
	
	write-verbose "Start OF New-NIMInitiator Command"
	write-verbose "-------------------------------"
	write-verbose "- Computername = $computername"
	write-verbose "- Alias = $alias"
	write-verbose "- Label = $label"
	write-verbose "- Initiator_Group_Name = $initator_group_name"
	write-verbose "- Initiator_Group_ID   = $initiator_group_id"
	write-verbose "- Access_Protocol = $access_protocol"
	write-verbose "- IP_Address = $IP_Address"
	write-verbose "- IQN = $iqn"
	write-verbose "- WWPN = $wwpn"
	write-verbose "-------------------------------"

	$returnarray=[system.array]@() 
	$wwpnset=[system.array]@()
	
	if ( Z_detect-NIMArray ) 													# Detecting the array
		{ 	$access_protocol =  $(Z_detect-NIMArrayProtocol $access_protocol )	# Discover if I can get to the array, and set the protocol type
			write-verbose "-Pass  = access_protocol=$access_protocol"
		}																		# this is where I set the number of iGroups on the array

		# this section fills in the Initiator Group ID, or the Name or the Computername, fills in any of the missing items.
	if ( -not $initiator_group_id )
		{	if ( $computername )
			{	if ( $initiator_group_name )	# if computername sent it, set the proper ID
					{	write-host "Both Computername and group name were specified, so obtaining group ID"
						if ( $z=$( get-niminitiatorgroup -name $name ) )
							{	$initiator_group_id = $($z.id)
								write-host "Successfully Found Initiator Group $($z.name)"
							} else
							{	Write-warning "Using group name $name the appropritate Initiator Group was not found"
							}
					} else # -not initiator_group_name 							# -not initiator_group_name
					{	write-warning  "Computername was specified, but name was not, doing a lookup to determine Initiator Group name"
						if ( $z=$( get-niminitiatorgroup -computername $computername ) )
							{	$initiator_group_id = $($z.id)
								$initiator_group_name= $($z.name)
								write-host "Successfully Found Initiator Group $($z.name)"
							} else
							{	Write-warning "Using Computername $computername the appropritate Initiator Group was not found"
							}
					}
			} else # -not computername
			{	if ( $initiator_group_name )							# if computername sent it, set the proper ID
					{	write-warning  "Computername was not specified, but name was, validating the name and setting the ID"
						if ( $z=$( get-niminitiatorgroup -name $initiator_group_name ) )
							{	$initiator_group_id = $($z.id)
								$initiator_group_name= $($z.name)
								write-host "Successfully Found Initiator Group $($z.name)"
								if ( Z_test-nimPSRemote $initiator_group_name )
									{ 	$Computername = $Initiator_group_name
										write-warning "Initiator Group name matches a valid hostname, setting computer name to $Computername"
									}
							} else
							{	Write-warning "Using Computername $computername the appropritate Initiator Group was not found"
							}
					} else # -not initiator_group_name
					{	write-warning "No Computer Name, or Initiator Group Name or ID was passed in, Assuming create a new Initiator Group for This Computer."
						$computername = (hostname)
						write-warning "Checking to see if localhost has Initiator Group defined."
						if ( $z=$( get-niminitiatorgroup -computername $computername ) )
							{	$initiator_group_id = $($z.id)
								write-host "Successfully Found Initiator Group $($z.name)"
							} else
							{	Write-warning "Using group name $name the appropritate Initiator Group was not found"
							}				
					}
			}
		} else # Initiator Group ID was SET
		{ 	if ( $z = $( get-niminitiatorgroup -id $initiator_group_id ) )
				{	$initiator_group_name = $z.name
				} else
				{	write-error "The supplied Initiator ID was not found"
				}
			if ( $computername )
				{	if ( -not $( Z_test-nimPSRemote $computername ) )
						{ 	write-warning "Cannot validate the computer named $computername"
						}
				} else
				{	if ( Z_test-nimPSRemote $initiator_group_name )
						{ 	$Computername = $Initiator_group_name
							write-warning "Initiator Group name matches a valid hostname, setting computer name to $Computername"	
						} else
						{	Write-warning "Using Computername $computername the appropritate Initiator Group was not found"
						}
				}
		}
		
		# this is where the command actually gets executed
	if ( $initiator_group_id ) # if I dont have this I cant do anything
		{	if ( -not $label )
				{ $label = $computername+"-IQN"
				}
			$label=""""+$label+""""
			if ($access_protocol -like "iscsi")
				{	if ( Z_test-nimPSRemote $computername )
						{	# lets attempt to get the IQN from the host
							if ( -not $alias )
								{	# should look like --> HOSTNAME-ROOT\ISCSIPRT\0000_0 which is how the OS sees it.
									$alias = $computername + "_" + $(invoke-command -computername $computername -scriptblock { (get-initiatorport | where {$_.connectiontype -like "iscsi" } ).instancename } ) 
								}
							$alias=""""+$alias+""""
							if ( -not $iqn ) 
								{ $iqn = invoke-command -computername $computername -scriptblock { (get-initiatorport | where {$_.connectiontype -like "iscsi"}).nodeaddress }
								}
						}
					write-host "Creating Initiator"
					$qiqn=""""+$iqn+""""
					$qip=""""+"*"+""""
					if ( $PSCmdlet.ShouldProcess('Issuing Command to Create Initiator Group') )
						{ 	# The Creation command goes here.
							write-host "Executing the following command;"
							write-host "new-nsinitiator -access_protocol $access_protocol -initiator_group_id $Initiator_Group_Id -label $label -ip_address $qip -iqn $qiqn"							
							new-nsinitiator -access_protocol $access_protocol -initiator_group_id $Initiator_Group_Id -label $label -ip_address $qip -iqn $qiqn -erroraction silentlycontinue
						} else
						{ 	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
							write-warning "This is the what-if or Initiator group failed required criteria: following command would be executed;"
							# write-warning "New-NSInitiator -Initiator_Group_ID $Initiator_Group_Id -access_protocol $access_protocol -alias $alias -label $label -iqn $iqn"		
							write-warning "New-NSInitiator -Initiator_Group_ID $Initiator_Group_Id -access_protocol $access_protocol -iqn $iqn"		
						}
				} else # access_protocol must be FC
				{	# Must be FC, Checking if FC ports exist on this server 
					if ( $computername )
						{	if ( $wwpndetected = invoke-command -computername $computername -scriptblock { (get-initiatorport | where {$_.connectiontype -like "Fibre Channel"}).nodeaddress } )
								{	foreach ( $wwpnfixed in $wwpndetected )
										{	$wwpnset+=$( Z_fix-NIMHostWWPN $wwpnfixed  )
										}
								}
						} else
						{	$wwpnset = $wwpn
						}
					if ( $wwpnset)
						{	write-host "Creating FC Initiator groups"
							$count=1
							foreach ($wwpni in $wwpnset)
								{	if ( -not $label )
										{ $label = $computername+"_HBA$count"
										}
									
									if ( -not $alias )
										{	# should look like --> HOSTNAME-ROOT\ISCSIPRT\0000_0 which is how the OS sees it.
											$alias = $computername + "_HBA$count"
										}
									$alias=""""+$alias+""""
									$label=""""+$label+""""
									if ( $PSCmdlet.ShouldProcess('Issuing Command to Create Initiator Group') )
										{ 	# The Creation command goes here.
											write-host "Executing the following command;"
											write-host "New-NSInitiator -Initiator_Group_ID $Initiator_Group_ID -access_protocol $access_protocol -alias $alias -label $label -wwpn $wwpni"
											$r= invoke-command -scriptblock { $( new-nsinitiator -Initiator_Group_Id $id -access_protocol $access_protocol -label $label -alias $alias -wwpn $wwpni ) }
											$r.PSObject.TypeNames.Insert(0,'Nimble.Initiator.Typename')
											$returnarray+=$r
										} else
										{ 	# since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-host
											write-warning "This is the what-if or Initiator group failed required criteria: following command would be executed;"
											write-warning "New-NSInitiator -Initiator_Group_ID $initiator_group_id -access_protocol $access_protocol -alias $alias -label $label -wwpn $wwpni"		
										}
									$count=$count+1
								}
						} else
						{	write-error "No WWPNs were either discovered or provided"
						}
				}
		}
	write-verbose ""
	write-verbose "-------------------------------"
	write-verbose "- Computername = $computername"
	write-verbose "- Alias = $alias"
	write-verbose "- Label = $label"
	write-verbose "- Initiator_Group_Name = $initator_group_name"
	write-verbose "- Initiator_Group_ID   = $initiator_group_id"
	write-verbose "- Access_Protocol = $access_protocol"
	write-verbose "- IP_Address = $IP_Address"
	write-verbose "- IQN = $iqn"
	write-verbose "- WWPN = $wwpn"
	write-verbose "-------------------------------"
	write-verbose "END OF New-NIMInitiator Command"
	$returnarray.PSObject.TypeNames.Insert(0,'Nimble.Initiator.Typename')
	return $returnarray
} # end the function
export-modulemember -function New-NimInitiator
