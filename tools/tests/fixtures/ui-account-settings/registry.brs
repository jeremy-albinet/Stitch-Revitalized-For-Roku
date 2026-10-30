' Only low-level storage is inert. All higher production config helpers execute.
function registry_read(key, section = invalid)
    if section = invalid then return invalid
    allValues = m.global.fixtureRegistry
    composite = section + ":" + key
    if allValues.doesExist(composite) then return allValues[composite]
    return invalid
end function
sub registry_write(key, value, section = invalid)
    if section = invalid then return
    allValues = m.global.fixtureRegistry
    allValues[section + ":" + key] = value
    m.global.fixtureRegistry = allValues
    m.global.fixtureWrites = m.global.fixtureWrites + 1
end sub
sub registry_delete(key, section = invalid)
    if section = invalid then return
    allValues = m.global.fixtureRegistry
    allValues.delete(section + ":" + key)
    m.global.fixtureRegistry = allValues
    m.global.fixtureDeletes = m.global.fixtureDeletes + 1
end sub
