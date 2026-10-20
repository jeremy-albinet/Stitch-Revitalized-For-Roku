' "Registry" is where Roku stores config

' Read config tree from json config file and return
function GetConfigTree()
    return ParseJSON(ReadAsciiFile("pkg:/settings/settings.json"))
end function


' Generic registry accessors
function registry_read(key, section = invalid)
    if section = invalid then return invalid
    reg = CreateObject("roRegistrySection", section)
    if reg.exists(key) then return reg.read(key)
    return invalid
end function

sub registry_write(key, value, section = invalid)
    if section = invalid then return
    reg = CreateObject("roRegistrySection", section)
    reg.write(key, value)
    reg.flush()
end sub

sub registry_delete(key, section = invalid)
    if section = invalid then return
    reg = CreateObject("roRegistrySection", section)
    reg.delete(key)
    reg.flush()
end sub


' "StitchRevitalizedForRoku" registry accessors for the default global settings
function get_setting(key, default = invalid)
    value = registry_read(key, m.global.appid)
    if value = invalid then return default
    return value
end function

sub set_setting(key, value)
    registry_write(key, value, m.global.appid)
end sub

sub unset_setting(key)
    registry_delete(key, m.global.appid)
end sub


' User registry accessors for the currently active user
function get_user_setting(key, default = invalid)
    if get_setting("active_user") = invalid then return default
    value = registry_read(key, get_setting("active_user"))
    if value = invalid

        ' Check for default in Config Tree
        configTree = GetConfigTree()
        configKey = findConfigTreeKey(key, configTree)

        if configKey <> invalid and configKey.default <> invalid
            set_user_setting(key, configKey.default) ' Set user setting to default
            return configKey.default
        end if

        return default
    end if
    return value
end function

sub set_user_setting(key, value)
    if get_setting("active_user") = invalid then return
    registry_write(key, value, get_setting("active_user"))
end sub

sub unset_user_setting(key)
    if get_setting("active_user") = invalid then return
    registry_delete(key, get_setting("active_user"))
end sub


' Profile index: JSON array of registry section names (one per saved account),
' stored in the global section.
function getProfiles() as object
    raw = get_setting("profiles")
    if raw = invalid then return []
    list = ParseJson(raw)
    if type(list) <> "roArray" then return []
    return list
end function

function profilesWith(list as object, section as string) as object
    for each item in list
        if item = section then return list
    end for
    list.push(section)
    return list
end function

function profilesWithout(list as object, section as string) as object
    result = []
    for each item in list
        if item <> section then result.push(item)
    end for
    return result
end function

sub saveProfile(section as string)
    if section = "$default$" then return
    set_setting("profiles", FormatJson(profilesWith(getProfiles(), section)))
end sub

sub removeProfile(section as string)
    set_setting("profiles", FormatJson(profilesWithout(getProfiles(), section)))
end sub

' Recursivly search the config tree for entry with settingname equal to key
function findConfigTreeKey(key as string, tree)
    for each item in tree
        if item.settingName <> invalid and item.settingName = key then return item

        if item.children <> invalid and item.children.Count() > 0
            result = findConfigTreeKey(key, item.children)
            if result <> invalid then return result
        end if
    end for

    return invalid
end function

' Added for backwards compatibility

function getTokenFromRegistry()
    return {
        access_token: get_user_setting("access_token", ""),
        refresh_token: get_user_setting("refresh_token", ""),
        login: get_user_setting("login", ""),
        device_id: get_user_setting("device_code", "")
    }
end function

function getRegistryKeys(section = invalid)
    Registry = CreateObject("roRegistry")
    if section = invalid
        output = {}
        for each section in Registry.GetSectionList()
            RegistrySection = CreateObject("roRegistrySection", section)
            output[section] = RegistrySection.GetKeyList()
        end for
    else
        RegistrySection = CreateObject("roRegistrySection", section)
        output = RegistrySection.GetKeyList()
    end if
    return output
end function

sub NukeRegistry(section = invalid)
    ? "Erasing Registry"
    Registry = CreateObject("roRegistry")
    if section = invalid
        for each section in Registry.GetSectionList()
            RegistrySection = CreateObject("roRegistrySection", section)
            for each key in RegistrySection.GetKeyList()
                print "Deleting " section + ":" key
                RegistrySection.Delete(key)
            end for
            RegistrySection.flush()
            Registry.Delete(section)
        end for
    else
        RegistrySection = CreateObject("roRegistrySection", section)
        for each key in RegistrySection.GetKeyList()
            print "Deleting " section + ":" key
            RegistrySection.Delete(key)
        end for
        RegistrySection.flush()
    end if

end sub

' Starts the built-in Enhanced Broadcasting splitter once, if its setting is on.
sub startBuiltinSplitter()
    if get_user_setting("proxy.builtin", "false") <> "true" or m.global.demuxServer <> invalid then return
    demuxServer = CreateObject("roSGNode", "DemuxServer")
    demuxServer.control = "RUN"
    m.global.addFields({ demuxServer: demuxServer })
end sub
