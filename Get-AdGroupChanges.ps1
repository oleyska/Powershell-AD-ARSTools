function Get-AdGroupChanges
{
param(
 [parameter(mandatory=$true)][alias('samaccountname','cn','username','groupname')]$name,
 [parameter(mandatory=$false)][alias('searchbase','domainname','forest')]$domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).name
)
# rewrite to correct format.
if ($domain -notlike '*DC=*')
    {
    $domain = 'DC=' + (($domain.split('.')) -join ',DC=')
    }
#Set up connection to forest
$de = New-Object directoryservices.DirectoryEntry("LDAP://$($domain)")
$ds = new-object directoryservices.directorysearcher($de)
[switch][alias("members","member")]$valuemeta =$true
#set an appropriate search filter for each type of object
$ds.filter = "(&(objectclass=group)(|(samaccountname=$name)(cn=$name)))"


#load up metadata attribs and search
$ds.propertiestoload.add("distinguishedname") > $null
$fu = $ds.findone()
if ($fu -ne $null) {
 $de = New-Object directoryservices.DirectoryEntry("LDAP://" + $fu.properties.distinguishedname[0])
} else {
 Write-Error "Object not found in AD"
 exit 1
}
$ds.searchroot = $de
$ds.propertiestoload.add("msDS-ReplAttributeMetaData") > $null
$ds.propertiestoload.add("msDS-ReplValueMetaData;range=0-999") > $Null

$fu = $ds.findone()
#what range name do we have can be 0-999, can be 0-*
$replValueMetaDataAttr = ($fu.Properties.PropertyNames | ? {$_ -like 'msds-replvaluemetadata*'})

$out = @()
#display the requested type of data
$xml = "<root>" + $fu.Properties.$replValueMetaDataAttr + "</root>"
$xml = [xml]$xml
$out=$xml.root.DS_REPL_VALUE_META_DATA | 
Select-Object @{name="Attribute"; expression={$_.pszAttributeName}},@{name="objectDN";expression={$_.pszObjectDN}},@{name='timecreated';expr={[datetime]::Parse($_.ftimeCreated).toUniversalTime()}},@{name='timeremoved';expr={[datetime]::Parse($_.ftimeDeleted).toUniversalTime()}} |
Sort-Object attribute

#do a loop until all ranges are completed.
if ($fu.Properties.$replValueMetaDataAttr.Count -eq 1000)
    {
    $range=1000
    do {
        [string]$rangeString = 'range=' + [string]$range + '-' + ($range + '999')
        #load up metadata attribs and search
        $de = New-Object directoryservices.DirectoryEntry("LDAP://" + $fu.properties.distinguishedname[0])
        $ds = new-object directoryservices.directorysearcher($de)
        $ds.searchroot = $de
        $ds.propertiestoload.add("distinguishedname") > $null
        $ds.propertiestoload.add("msDS-ReplAttributeMetaData") > $null
        $ds.propertiestoload.add("msDS-ReplValueMetaData;$($rangeString)") > $Null

        $re = $ds.findone()
        #what range name do we have can be 0-999, can be 0-*
        $replValueMetaDataAttr = ($re.Properties.PropertyNames | ? {$_ -like 'msds-replvaluemetadata*'})

        #display the requested type of data
        $xml = "<root>" + $re.Properties.$replValueMetaDataAttr + "</root>"
        $xml = [xml]$xml
        $out+=$xml.root.DS_REPL_VALUE_META_DATA | 
        Select-Object @{name="Attribute"; expression={$_.pszAttributeName}},@{name="objectDN";expression={$_.pszObjectDN}},@{name='timecreated';expr={[datetime]::Parse($_.ftimeCreated).toUniversalTime()}},@{name='timeremoved';expr={[datetime]::Parse($_.ftimeDeleted).toUniversalTime()}} |
        Sort-Object attribute
        $range = $range + 1000
    }
    while ( !$replValueMetaDataAttr.Contains('*'))
    }
Write-Output $out
}