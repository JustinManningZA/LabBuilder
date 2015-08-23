#
# This is a PowerShell Unit Test file.
# You need a unit test framework such as Pester to run PowerShell Unit tests. 
# You can download Pester from http://go.microsoft.com/fwlink/?LinkID=534084
#

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

Remove-Module LabBuilder -ErrorAction SilentlyContinue
Import-Module "$here\LabBuilder.psd1"
$TestConfigPath = "$here\Tests\PesterTestConfig.xml"
Write-Host "Running from $Here"

##########################################################################################################################################
Describe "Get-LabConfiguration" {
	Context "No parameter is passed" {
		It "Fails" {
			{ Get-LabConfiguration } | Should Throw
		}
	}
	Context "Path is provided but file does not exist" {
		It "Fails" {
			{ Get-LabConfiguration -Path 'c:\doesntexist.xml' } | Should Throw
		}
	}
	Context "Path is provided but file does not exist" {
		It "Fails" {
			{ Get-LabConfiguration -Path 'c:\doesntexist.xml' } | Should Throw
		}
	}
	Context "Path is provided and valid XML file exists" {
		It "Returns XmlDocument object with valid content" {
			$Config = Get-LabConfiguration -Path $TestConfigPath
			$Config.GetType().Name | Should Be 'XmlDocument'
			$Config.labbuilderconfig | Should Not Be $null
		}
	}
	Context "Content is provided but is empty" {
		It "Fails" {
			{ Get-LabConfiguration -Content '' } | Should Throw
		}
	}
	Context "Content is provided and contains valid XML" {
		It "Returns XmlDocument object with valid content" {
			$Config = Get-LabConfiguration -Content (Get-Content -Path $TestConfigPath -Raw)
			$Config.GetType().Name | Should Be 'XmlDocument'
			$Config.labbuilderconfig | Should Not Be $null
		}
	}
}
##########################################################################################################################################

##########################################################################################################################################
Describe "Test-LabConfiguration" {
	$Config = Get-LabConfiguration -Path $TestConfigPath
	Remove-Item -Path $Config.labbuilderconfig.SelectNodes('settings').vmpath -Recurse -Force -ErrorAction SilentlyContinue

	Context "No parameter is passed" {
		It "Fails" {
			{ Test-LabConfiguration } | Should Throw
		}
	}
	Context "Valid Configuration is provided and VMPath folder does not exist" {
		It "Fails" {
			{ Test-LabConfiguration -Configuration $Config } | Should Throw
		}
	}
	
	New-Item -Path $Config.labbuilderconfig.SelectNodes('settings').vmpath -ItemType Directory

	Context "Valid Configuration is provided and VHDParentPath folder does not exist" {
		It "Fails" {
			{ Test-LabConfiguration -Configuration $Config } | Should Throw
		}
	}
	
	New-Item -Path $Config.labbuilderconfig.SelectNodes('settings').vhdparentpath -ItemType Directory

	Context "Valid Configuration is provided and all paths exist" {
		It "Returns True" {
			Test-LabConfiguration -Configuration $Config | Should Be $True
		}
	}
	Remove-Item -Path $Config.labbuilderconfig.SelectNodes('settings').vmpath -Recurse -Force -ErrorAction SilentlyContinue
}
##########################################################################################################################################

##########################################################################################################################################
Describe "Install-LabHyperV" {
	$Config = Get-LabConfiguration -Path $TestConfigPath

	Context "The function exists" {
		It "Returns True" {
			If ((Get-CimInstance Win32_OperatingSystem).ProductType -eq 1) {
				Mock Get-WindowsOptionalFeature { return [PSCustomObject]@{ Name = 'Dummy'; State = 'Enabled'; } }
			} Else {
				Mock Get-WindowsFeature { return [PSCustomObject]@{ Name = 'Dummy'; Installed = $false; } }
			}
			Install-LabHyperV | Should Be $True
		}
	}
}
##########################################################################################################################################

##########################################################################################################################################
Describe "Initialize-LabHyperV" {
	$Config = Get-LabConfiguration -Path $TestConfigPath
	
	$CurrentMacAddressMinimum = (Get-VMHost).MacAddressMinimum
	$CurrentMacAddressMaximum = (Get-VMHost).MacAddressMaximum
	Set-VMHost -MacAddressMinimum '001000000000' -MacAddressMaximum '0010000000FF'
	Context "No parameter is passed" {
		It "Fails" {
			{ Initialize-LabHyperV } | Should Throw
		}
	}
	Context "Valid configuration is passed" {
		It "Returns True" {
			Initialize-LabHyperV -Config $Config | Should Be $True
		}
		It "MacAddressMinumum should be $($Config.labbuilderconfig.SelectNodes('settings').macaddressminimum)" {
			(Get-VMHost).MacAddressMinimum | Should Be $Config.labbuilderconfig.SelectNodes('settings').macaddressminimum
		}
		It "MacAddressMaximum should be $($Config.labbuilderconfig.SelectNodes('settings').macaddressmaximum)" {
			(Get-VMHost).MacAddressMaximum | Should Be $Config.labbuilderconfig.SelectNodes('settings').macaddressmaximum
		}
	}
	Set-VMHost -MacAddressMinimum $CurrentMacAddressMinimum -MacAddressMaximum $CurrentMacAddressMaximum
}
##########################################################################################################################################

##########################################################################################################################################
Describe "Initialize-LabDSC" {
	$Config = Get-LabConfiguration -Path $TestConfigPath

	Context "No parameter is passed" {
		It "Fails" {
			{ Initialize-LabDSC } | Should Throw
		}
	}
}
##########################################################################################################################################

##########################################################################################################################################
Describe "Get-LabSwitches" {
	$Config = Get-LabConfiguration -Path $TestConfigPath
	$ExpectedSwtiches = @( 
				@{ name="General Purpose External"; type="External"; vlan=$null; adapters=[System.Collections.Hashtable[]]@(
					@{ name="Cluster"; macaddress="00155D010701" },
					@{ name="Management"; macaddress="00155D010702" },
					@{ name="SMB"; macaddress="00155D010703" },
					@{ name="LM"; macaddress="00155D010704" }
					)
				},
				@{ name="Pester Test Private Vlan"; type="Private"; vlan="2"; adapters=@() },
				@{ name="Pester Test Private"; type="Private"; vlan=$null; adapters=@() },
				@{ name="Pester Test Internal Vlan"; type="Internal"; vlan="3"; adapters=@() },
				@{ name="Pester Test Internal"; type="Internal"; vlan=$null; adapters=@() }
			)
	Context "No parameter is passed" {
		It "Fails" {
			{ Get-LabSwitches } | Should Throw
		}
	}
	Context "Valid configuration is passed" {
		$Switches = Get-LabSwitches -Config $Config
		Set-Content -Path "$($ENV:Temp)\Switches.json" -Value ($Switches | ConvertTo-Json -Depth 10)
		Set-Content -Path "$($ENV:Temp)\ExpectedSwitches.json" -Value ($ExpectedSwtiches | ConvertTo-Json -Depth 10)
		
		It "Returns 5 Switch Items" {
			$Switches.Count | Should Be 5
		}
		It "Returns Switches Object that matches Expected Object" {
			[String]::Compare(($Switches | ConvertTo-Json -10),($ExpectedSwtiches | ConvertTo-Json -10),$true) | Should Be 0
		}
	}
}
##########################################################################################################################################