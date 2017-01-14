NimbleAdvancedPowerShellToolkit

This is a PowerShell module is designed to operate as a layer above the NimblePowerShellToolk and adds support for pipeline input from various Microsoft commands and also offers saftey checks as well as troubleshooting commands.

If you currently are not using the NimblePowerShellToolkit, please download it and connect to your Nimble Storage via the 'Connect-NSGroup' command before using any of these Advanced Commands.

This is not fully featured or tested and new resilient commands are being added all the time, but pull requests would be welcome!
Instructions

# One time setup
    # Download the repository
    # Unblock the zip
    # Extract the NimbleAdvancedPowerShellToolkit folder to a module path (e.g. $env:USERPROFILE\Documents\WindowsPowerShell\Modules\)

    #Simple alternative, if you have PowerShell 5, or the PowerShellGet module:
        Install-Module NimbleAdvancedPowerShellToolkit

# Import the module.
    Import-Module NimbleAdvancedPowerShellToolkit    #Alternatively, Import-Module \\Path\To\NimbleAdvancedPowerShellToolkit

# Get commands in the module
    Get-Command -Module NimbleAdvancedPowerShellToolkit

# Get help
    Get-Help Get-NIMObject -Full
    Get-Help about_NimbleAdvancedPowerShellToolkit