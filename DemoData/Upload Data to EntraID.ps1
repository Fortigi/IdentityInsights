$TenantName = 'iidemos.onmicrosoft.com'
$Users = Import-Csv -Path ".\Users.csv" -Delimiter ";"
$Groups = Import-Csv -Path ".\Groups.csv" -Delimiter ";"

Import-Module FortigiGraph

Get-FGAccessTokenInteractive -TenantId $TenantName

Foreach ($Group in $Groups) {
    New-FGGroup -DisplayName $Group.GroupNames -SecurityEnabled $True -Description ("Group for " + $Group.GroupNames)
}

Foreach ($User in $Users) {

    $UserObject = Get-FGUser -userPrincipalName $user.UPN

    If ($User.EmployeeID) {
        $Updates = @{
            givenName   = $User.FirstName
            surname     = $User.LastName
            displayName = $User.DisplayName
            department  = $User.Department
            jobTitle    = $user.Title
            employeeId  = $User.EmployeeID
            companyName = $User.Company
        }
    }
    else {
        $Updates = @{
            givenName   = $User.FirstName
            surname     = $User.LastName
            displayName = $User.DisplayName
            department  = $User.Department
            jobTitle    = $user.Title
            companyName = $User.Company
        }
    }
    Set-FGUser -ObjectId $UserObject.id -Updates $Updates

}



Foreach ($User in $Users) {

    $UserObject = Get-FGUser -userPrincipalName $user.UPN

    $UserAttbs = ($User | Get-Member | Where-Object { $_.MemberType -eq "NoteProperty" }).Name

    Foreach ($UserAttb in $UserAttbs) {

        If ($User.$UserAttb -eq "x") {

            $GroupObject = Get-FGGroup -DisplayName $UserAttb
            Add-FGGroupMember -Id $GroupObject.id -MemberId $UserObject.id
        }
    }


}