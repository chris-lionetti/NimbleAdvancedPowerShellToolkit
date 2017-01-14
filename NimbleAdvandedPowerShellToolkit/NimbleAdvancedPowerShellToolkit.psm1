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
		[validateset("iSCSI","fc","Fibre Channel")]
		[string]
		$access_protocol="" ,

		[Parameter (	HelpMessage="Enter the collection of Valid Target Subnets if using iSCSI." ) ]
		[string[]] $target_subnets=""
	)

$returnarray=[system.array]@()
if ($access_protocol -like "Fibre Channel") { $access_protocol = "FC" } # Fix the name to be Nimble Complient from MS standard
write-verbose "-Pass Values of the variables equal the following;"
write-verbose "-Pass  = Computername=$Computername"
write-verbose "-Pass  = name=$name"
write-verbose "-Pass  = description=$description"
write-verbose "-Pass  = access_protocol=$access_protocol"
write-verbose "-Pass  = target_subnets=$target_subnets"
write-verbose "-Pass  = -Force =$force"

if ( -not $ComputerName ) 
	{ $ComputerName = (hostname) 
	  write-warning "No Computername was Passed in as a parameter"
	}	
$x=$computername.count
write-debug "number of items in Computername = $x"
$skipall=$false
foreach ( $Computer in $ComputerName )
{ if ( $Computer -contains (hostname) )
	 { write-verbose "This computername is in fact the localhost"
	   $uselocalhost=$true
	 } else
	 { write-warning "This computername doesnt match the localhost"
	   $uselocalhost=$false
	 }
  if ( -not $name ) # if the group name is blank, this will default it to the computer name
	 { $name = $Computer
	   write-warning "Hostname was left blank, settings it same as the Computer=$Computer"	
	 } else
	 { write-verbose "Initiator Group name was specified as $name"
	 }
  # Detecting the array
  if ( Get-nsArray -ErrorAction SilentlyContinue ) 
	 { # validating if an Array is connected$ArrayName
	   $ArrayName=((Get-nsarray).name)
	   $c=(get-nsinitiatorgroup).count
	   Write-host "Validating Connectivitity to Array named = $arrayname"
	 } else
	 { # No need to continue if I cant connect to an array.
	   write-error "Could not connect to a valid array."
	   write-error "Use Connect-NSArray to connect."
	   break
	 }
  if ( $uselocalhost )
     { write-verbose "All commands will be run locally"
	 } else
	 { if ( invoke-command -ComputerName $computer -scriptblock { get-host } -ErrorAction SilentlyContinue )
	      { write-host "PowerShell Remoting run successfully against remote host $Computer"
	      } else
		  { write-warning "Remote PowerShell connectivity to host named $Computer was denied."
		    if ( $force )
			   { write-warning "Force was used so ignoring error and allowing creation to take place."
			   } else 
			   { $skipall=$true
				 write-warning "Creation of new group will not be allowed due to lack of validation"
			   }
		  }
	 }
  # Determine if the target array is iscsi or FC
  # once we have an array that supports FC and iSCSI at same time will have to update this section.
  if ( get-NSFibreChannelPort )
     { write-Output "Detected that this array is FC based"
	   if ( $access_protocol -eq "iscsi")
		  { write-warning "This Access Protocol cannot be iSCSI"
		  }
	   write-Output "Setting Access to this Array as Fibre Channel"
	   $access_protocol="fc"
     } else
     { write-output "Detected that this array is iSCSI based"
	   if ( $access_protocol -eq "fc")
	      { write-warning "This Access Protocol cannot be FC."
		  }
	   write-output "Setting Access to this Array as iscsi"
	   $access_protocol="iscsi"
     }

  # detect if this servers initiator group already exists
  write-output "Finding if Existing Initiator Group Exists"
  $alreadyExists=$false
  write-verbose "Detected $Counter Initiator Groups on the Array, Checking them now"
  $cd=$c # Countdown = $counter
  foreach ( $iGroup in get-nsinitiatorgroup ) 
    { # compair my target subnet to each subnet on the array
      start-sleep -m 50
      Write-Progress -activity "Searching Existing Initiator Groups" `
	                 -status "Progress:" `
					 -percentcomplete ( ($c-(--$cd)) / $c * 100 ) `
					 -currentoperation $($igroup.name)
      if ( $name -like $($igroup.name) )
         { # What to do when a parameter subnet matches an array subnet   
	       write-output "Found Match Checking $name against $($igroup.name)"
	       $alreadyExists=$true
	       $name=$($igroup.name)
	       break 					# dont need to continue looking, found it
	     } else
         { # only Verbose letting me know of a compair miss
	       write-debug "No match checking $name against $($igroup.name)"
         }
    }
  Write-Progress -activity "Searching Existing Initiator Groups" -status "Progress:" -percentcomplete ( 100 )
	   
# This is a initiator group for the servers, validate it has those type of HBAs
  if ( -not $skipall )
 	 { write-verbose "This command is being asked to create an iGroup for THIS server $Computer"
	   if ($access_protocol -like "iscsi")
	      {	# Must be iSCSI, Checking if iSCSI service is runningif
	        if ( (invoke-command -computername $computer -scriptblock {get-initiatorport} | where {$_.connectiontype -like "iscsi"}) )
			   { Write-output "The server has an iSCSI Initiator configured"
			   } else
			   { Write-warning "The server has NO iscsi Initiator configured"
			   }
	      } else
	      { # Must be FC, Checking if FC ports exist on this server 
	        if ( (invoke-command -computername $computer -scriptblock {get-initiatorport} | where {$_.connectiontype -like "Fibre Channel"} ) )
		       { Write-output "The server has an FC Initiator configured"
		       } else
		       { Write-warning "The server has NO FC Initiator configured"
		       }
	      }
	   if ( -not $description )
		  { # first determine if the Description is set on the target computer
		    $wmio = invoke-command -computername $computer -scriptblock { get-wmiobject -class win32_operatingsystem }
		    if ( -not $wmio.description )
			   { # if not set, lets set one, namely the Machinename + OS Version + Cluster Name (if exists)
			     if ( get-cluster )
				    { $clus=" - Clustername:" + (get-cluster).name
				    } else
				    { $clus = ""
				    }
			     $description = $Computer + " - " + $wmio.caption + $clus
			     write-warning "No Description Provided or Detected on Host, setting it as $description"
			   } else
			   { write-verbose "No Description Provided, using the detected computer description $description"
			     $description = $wmio.description
			   }
		  }
	  
	 } else 
	 { write-warning "Command is unable to verify the remote hosts initiators."
	   write-warning "This command will only create the initiator group if the Confirm flag is set fo $false or the -force option is used"
	 }
	
  $VTSL="" # Validated Target Subnet List
  foreach( $tsub in $target_subnets )
	{ # walk through each Subnet that was sent in via parameter
      write-verbose "Detecting if Target Subnet $tsub exists on Array"
      foreach($dsub in get-nssubnet)
	    { # compair my target subnet to each subnet on the array
	      if ( $tsub -eq $dsub.name ) # These compairs are already case insensitive
		     { # What to do when a parameter subnet matches an array subnet
			   $outmsg=$tsub+" matches Target Subnet "+$dsub.name+" with Target Subnet ID "+$dsub.id
			   write-output $outmsg
			   if ( $dsub.allow_iscsi )
				  { write-verbose "This subnet to authorized for $tsub Target Subnet"
			        if ( $VTSL )
					   { $VTSL+="," + $dsub.name
					   } else
					   { $VTSL=$dsub.name
					   }
					break # dont need to continue looking for this target subnet, found it.
				  } else
				  { write-warning "The $tsub Target Subnet does not allow iSCSI communication"
				  }
 			 } else
		     { write-verbose "No match checking Target Subnet $tsub against Target Subnet $($dsub.name)"
		     }
		}	
	}

  write-verbose "this is the cleansed list $VTSL versus the original list $target_subnets"
  if ( $VTSL )
     { write-verbose "this is the cleansed list $VTSL"
       $target_subnets=$VTSL
     } else
     { write-verbose "The list of Target Subnets = *"
	   $target_subnets="*"
     }		
  write-verbose "The Cleansed list of Subnets is $target_subnets"   
  $description=""""+$description+""""
  $target_subnets=""""+$target_subnets+"""" 
  write-Host "Following Values use to create final command;"
  write-Host "Computername = $Computer"
  write-Host "Use Localhost? $uselocalhost"
  write-Host "Name = $name"
  write-Host "Description = $description"
  write-Host "access_protocol = $access_protocol"
  write-Host "target_subnets = $target_subnets"
  if ( $alreadyexists )
     { write-warning "This Initiator Group Already Exists. Array will not be modified"
     } else
     { if ( $PSCmdlet.ShouldProcess('Issuing Command to Create Initiator Group') )
	      { # The Creation command goes here.
  	        write-output "Executing the following command;"
	        write-output "New-NSInitiatorGroup -name $name -access_protocol $access_protocol -description $description"
	        New-NSInitiatorGroup -name $name -access_protocol $access_protocol -description $description
	      } else
	      { # since the command was sent using the WHATIF flag, just inform the user what we WOULD have donewrite-output
	        write-warning "This is the what-if: following command would be executed;"
	        write-warning "New-NSInitiatorGroup -name $name -access_protocol $access_protocol -description $description"		
	  	  }
	 }	
	
  # This will return as the object the initiator group it just created, or if it already exists, the current one.
  $r=(get-nsinitiatorgroup -name ($name)) 
  # reset all the variables if multiple servers were selected.
  $alreadyExists=$false
  $name=""
  $skipall=$false
  $description=""
  if ( $r ) # only want to add a value if the iGroup returns valid
     { $r | add-member -type NoteProperty -name ComputerName -value $computer
	   $r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')	}
  $returnarray+=$r
} # end the For Loop

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
relavent initiator groups.
    
.PARAMETER Name
Specifies the common name used to refer to this Initiator Group. This is commonly the same as the hostname 
of the server. If not specified, the command will default to all. This can be a single name or a list of names
seperated by commas

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

name             id                                         access_protocol computerName description       
----             --                                         --------------- ------------ -----------       
sql-p            0247a5f2220a9575e0000000000000000000000027 iscsi                        My Production Sql Server                  
sql-c            0247a5f2220a9575e0000000000000000000000034 iscsi     					 My Dev Sql Server
Oracle-p         0247a5f2220a9575e0000000000000000000000037 iscsi                        My Production Oracle Server                 
Oracle-c         0247a5f2220a9575e0000000000000000000000044 iscsi     					 My Dev Oracle Server

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-NimInitiatorGroup -name Server1

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-NimInitiatorGroup -name Server1,Server2,Server3

.EXAMPLE
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-NimInitiatorGroup -name Server1 id 1a58cccb25ab411db2000000000000000000000004
# This will return and initiator with a name of Server1 and additionally the specified id

.EXAMPLE
This example will create Initiator Groups for ALL of the members of a Windows Cluster using PowerShell Remoting.
C:\PS> Connect-NSGroup 10.18.128.190
C:\PS> Get-ClusterNode | ForEach-Object { Get-ClusterNode $_.NodeName | Get-NimInitiatorGroup }

.EXAMPLE
PS:> Get-NimInitiatorGroup -name sql-p,node2 -id 0247A5f2220A9575E0000000000000000000000034
Validating Connectivitity to Array named = mcs460gx2
Found correct Initiator Group, sql-p matches sql-p
Found correct Initiator Group, 0247A5f2220A9575E0000000000000000000000034 matches 0247a5f2220a9575e0000000000000000000000034
WARNING: Initiator group that matches name node2 was not found

name                       id                                         access_protocol computerName        description       
----                       --                                         --------------- ------------        -----------       
sql-p                      0247a5f2220a9575e0000000000000000000000027 iscsi                                                 
sql-c                      0247a5f2220a9575e0000000000000000000000034 iscsi                                                 
#>

function Get-NimInitiatorGroup 
{
	 [cmdletBinding()]
  param
    (	[parameter ( 	ValueFromPipeline=$True,
						ValueFromPipelineByPropertyName,
					 	HelpMessage="Enter a one or more Names seperated by commas.")]
		[Alias("ComputerName", "Cn", "NodeName", "_SERVER")] 
		[string[]] 
		$name="",

		[parameter ( 	HelpMessage="Enter a one or more Initiator Groups.")]
		[string] 
		$id=""
	)
	
$returnarray=[system.array]@()
if ( Get-nsArray -ErrorAction SilentlyContinue ) 
	 { # validating if an Array is connected$ArrayName
	   $ArrayName=((Get-nsarray).name)
	   Write-host "Validating Connectivitity to Array named = $arrayname"
	   $c=(get-nsinitiatorgroup).count # set the variable used to see progress
	 } else
	 { # No need to continue if I cant connect to an array.
	   write-error "Could not connect to a valid array."
	   write-error "Use Connect-NSArray to connect."
	   break
	 }
	 
if ( -not $name)
	{ Write-verbose "No Name variable was given." 
	} else
	{ write-verbose "Name Argument Passed in is $name"
	  foreach ( $n in $name )
		{ $cd=$c # countdown = count
          write-verbose "Detected $Counter Initiator Groups on the Array, Checking them now"
		  $foundname=$false
		  foreach ( $igroup in get-NSInitiatorgroup )
			{ start-sleep -m 25
			  Write-Progress -activity "Searching Existing Initiator Groups" -status "Progress:" `
							 -percentcomplete ( ($c-(--$cd)) / $c * 100 ) -currentoperation $($igroup.name)
              if ( $n -eq $igroup.name)
				 { write-output "Found correct Initiator Group, $n matches $($igroup.name)"
				   $r=$igroup
	               $r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
				   $returnarray+=$r
				   $foundname=$true
				 } else
				 { write-debug "Initiator compair false - $n not equal to $($igroup.name)"
				 }			  
			} 	  
		  Write-Progress -activity "Searching Existing Initiator Groups" -status "Progress:" -percentcomplete ( 100 )
		  if ( -not $foundname )
			{	write-warning "Initiator group that matches name $n was not found"
			}
		}
    }
if ( -not $id)
	{ # then 
	  Write-Verbose "No Id's were give to search for."
	} else
	{ # else 
	  foreach ( $idd in $id )
		{ $cd=$c # countdown = count
          write-verbose "Detected $Counter Initiator Groups on the Array, Checking them now"
		  $foundid=$false
		  foreach ( $igroup in get-NSInitiatorgroup )
			{ start-sleep -m 25
			  Write-Progress -activity "Searching Existing Initiator Groups" `
							 -status "Progress:" `
							 -percentcomplete ( ($c-(--$cd)) / $c * 100 ) `
							 -currentoperation $($igroup.id)
              if ( $idd -eq $igroup.id )
				 { # then
				   $r=$igroup
				   write-output "Found correct Initiator Group, $idd matches $($igroup.id)"
				   $r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
				   $returnarray+=$r
				   $foundID=$true
				 } else
				 { # else
				   write-debug "Initiator compair false - $idd not equal to $($igroup.id)"
				 }			  
			} 	  
		  Write-Progress -activity "Searching Existing Initiator Groups" -status "Progress:" -percentcomplete ( 100 )
		  if ( -not $foundid )
			{ write-warning "Initiator Group that matches id $idd was not found"
			}
		}
    }

if ( -not $name -and -not $id )
		{ # They must want Everything 
		  write-host "Gathering All Initiator Groups"
		  $cd=$c # countdown=counter
          write-verbose "Detected $Counter Initiator Groups on the Array, Checking them now"
		  foreach ( $igroup in get-NSInitiatorgroup )
			{ $r=$igroup
			  start-sleep -m 25
			  Write-Progress -activity "Gathering Existing Initiator Groups" `
							 -status "Progress:" `
							 -percentcomplete ( ($c-(--$cd)) / $counter * 100 ) `
							 -currentoperation $($igroup.name)
	          $r.PSObject.TypeNames.Insert(0,'Nimble.InitiatorGroup.Typename')
			  $returnarray+=$r			  
			} 	  
		  Write-Progress -activity "Gathering Finished for Initiator Groups" -status "Progress:" -percentcomplete ( 100 )
		}
		
return $returnarray
}
export-modulemember -function Get-NimInitiatorGroup 	
	
	