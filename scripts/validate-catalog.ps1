<#
    Validates the catalog's index.json against the matching contract the
    installer enforces.

    The failure this exists to prevent is specific. If the catalog writes
    'lang:ts' where the installer looks for 'lang:typescript', nothing breaks
    loudly - the artifact simply never gets selected, and the developer who
    wrote it has no way to know. That is a success with missing content, which
    the transport spike identified as the dangerous outcome on this system.
    Every check below exists to turn that silence into a CI failure.

    This validator and the installer's Read-AcceleratorCatalogIndex are one rule
    expressed twice. Where the installer is strict, this is strict - notably the
    case-sensitive vocabulary comparison. Being more permissive here would let an
    artifact pass CI and then install nowhere; being stricter would fail an
    artifact that installs fine.

    The one deliberate divergence is the reporting shape. The installer throws on
    the first problem because it must not proceed with a catalog it does not
    understand. CI has no such constraint, and an author who fixes one typo per
    push soon stops trusting the check - so every fault is collected and
    reported together.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $IndexPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The five dimensions the installer knows. Deliberately wider than the set
# matching actually filters on, which stops at 'agents': topics is a *selection*
# dimension, not a filter - an artifact's topics decide whether a developer who
# already matched the filter actually wants it. But the vocabulary still
# publishes topics, and this validator still has to check them.
$VocabularyDimensions = @('languages', 'frameworks', 'layout', 'agents', 'topics')

$SupportedSchemaVersion = '1'

$errors = [System.Collections.Generic.List[string]]::new()

function Add-CatalogError {
    <#
        Records one fault and writes it to the host as it is found, so a CI log
        reads top to bottom instead of only at the summary.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    $errors.Add($Message)
    Write-Host "ERROR: $Message"
}

function Get-ArtifactId {
    <#
        Resolves an artifact's id for use in diagnostics, falling back to its
        position when the id itself is missing.

        Called before any other property is read, because every message below
        interpolates the id - reading it unguarded under strict mode would kill
        the error path with a bare "property cannot be found" naming nothing.
        The position is the only handle an author has on an artifact that has no
        id, so an error must never come back naming neither.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Artifact,

        [Parameter(Mandatory)]
        [int] $Index
    )

    if ($null -ne $Artifact -and
        $Artifact -isnot [string] -and
        $null -ne $Artifact.PSObject.Properties['id'] -and
        -not [string]::IsNullOrWhiteSpace($Artifact.id)) {
        return $Artifact.id
    }

    return "<artifact at index $Index>"
}

function Test-CatalogArtifact {
    <#
        Validates one artifact against the catalog vocabulary, recording every
        problem it finds rather than returning at the first.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Artifact,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Vocabulary,

        [Parameter(Mandatory)]
        [int] $Index
    )

    $id = Get-ArtifactId -Artifact $Artifact -Index $Index

    if ($null -eq $Artifact -or $Artifact -is [string] -or $Artifact -is [ValueType]) {
        Add-CatalogError "Catalog artifact at index $Index is not an object. Each entry in the artifacts list must be a JSON object with an id."
        return
    }

    # Fixtures are transport test data, not catalog content. The flag suppresses
    # every check below it, so who may claim it is constrained: a typo'd
    # fixture:true on a real artifact would make that artifact vanish from every
    # install with no error anywhere.
    #
    # -eq $true rather than a truthiness test. The string 'false' is truthy in
    # PowerShell, so "fixture": "false" would otherwise read as a fixture and
    # silently hide a real artifact - the precise shape of the failure this
    # whole validator exists to prevent.
    if ($null -ne $Artifact.PSObject.Properties['fixture'] -and $Artifact.fixture -eq $true) {
        if ($id -notlike 'AS-SPIKE-*') {
            Add-CatalogError "Artifact $id declares fixture: true, but only AS-SPIKE-* artifacts may. The flag exempts an artifact from all matching validation and hides it from every install."
        }
        return
    }

    $hasAppliesTo = $null -ne $Artifact.PSObject.Properties['applies_to'] -and $null -ne $Artifact.applies_to
    $hasStrength = $null -ne $Artifact.PSObject.Properties['strength'] -and $null -ne $Artifact.strength

    if (-not $hasAppliesTo) {
        # Absent is not the same as {}. Requiring it explicitly means "applies
        # everywhere" can never be confused with "the author forgot".
        Add-CatalogError "Artifact $id is missing required field 'applies_to'. Write applies_to as {} for a universally applicable artifact."
    }

    if (-not $hasStrength) {
        Add-CatalogError "Artifact $id is missing required field 'strength'. Expected 'always' or 'on-demand'."
    }

    if ($hasStrength -and $Artifact.strength -cne 'always' -and $Artifact.strength -cne 'on-demand') {
        Add-CatalogError "Artifact $id has unknown strength '$($Artifact.strength)'. Expected 'always' or 'on-demand'."
    }

    if ($hasAppliesTo) {
        # A scalar applies_to - "applies_to": "typescript" - has no properties to
        # walk, so the loop below would pass it silently and the installer would
        # then treat the artifact as applying to every profile.
        if ($Artifact.applies_to -is [string] -or $Artifact.applies_to -is [ValueType] -or $Artifact.applies_to -is [array]) {
            Add-CatalogError "Artifact $id declares applies_to as the scalar '$($Artifact.applies_to)' rather than an object. Write applies_to as {} for a universally applicable artifact."
        } else {
            foreach ($declared in $Artifact.applies_to.PSObject.Properties) {
                # Case-sensitive throughout: the vocabulary is a closed lower-case
                # set and the installer compares with -ccontains. Being more
                # permissive here means an artifact passes CI and then matches
                # nothing.
                if ($VocabularyDimensions -cnotcontains $declared.Name) {
                    Add-CatalogError "Artifact $id declares unknown dimension '$($declared.Name)'. Known dimensions: $($VocabularyDimensions -join ', ')."
                    continue
                }

                # A dimension the artifact references but the vocabulary omits
                # leaves the allowed set empty, which would report the value as
                # merely "not allowed" and send the author hunting in the
                # artifact when the vocabulary is at fault.
                if ($null -eq $Vocabulary -or $null -eq $Vocabulary.PSObject.Properties[$declared.Name]) {
                    Add-CatalogError "Artifact $id declares dimension '$($declared.Name)', which the catalog vocabulary does not publish."
                    continue
                }

                $allowed = @($Vocabulary.($declared.Name))
                foreach ($value in @($declared.Value)) {
                    if ($allowed -cnotcontains $value) {
                        Add-CatalogError "Artifact $id declares '$value' in dimension '$($declared.Name)', which is not in the catalog vocabulary. Allowed: $($allowed -join ', ')."
                    }
                }
            }
        }
    }

    $topics = @()
    if ($null -ne $Artifact.PSObject.Properties['topics'] -and $null -ne $Artifact.topics) {
        $topics = @($Artifact.topics)
    }

    if ($topics.Count -gt 0 -and ($null -eq $Vocabulary -or $null -eq $Vocabulary.PSObject.Properties['topics'])) {
        Add-CatalogError "Artifact $id declares topics, which the catalog vocabulary does not publish."
    } else {
        foreach ($topic in $topics) {
            if (@($Vocabulary.topics) -cnotcontains $topic) {
                Add-CatalogError "Artifact $id declares topic '$topic', which is not in the catalog vocabulary. Allowed: $(@($Vocabulary.topics) -join ', ')."
            }
        }
    }

    # An on-demand artifact with no topics can never be selected by any profile,
    # so it is dead catalog content rather than an artifact that merely happens
    # not to match today.
    if ($hasStrength -and $Artifact.strength -ceq 'on-demand' -and $topics.Count -eq 0) {
        Add-CatalogError "Artifact $id is on-demand but declares no topics, so no profile could ever select it."
    }
}

# A missing or malformed file is a broken invocation, not catalog content that
# failed validation, so these throw rather than joining the error list. There is
# nothing here for an author to fix in the catalog.
if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    throw "Catalog index not found: $IndexPath"
}

try {
    # ConvertFrom-Json's own parse error quotes the offending token but never the
    # file, and a catalog can hold many index files across many refs.
    $index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Catalog index at $IndexPath is not valid JSON: $($_.Exception.Message)"
}

if ($null -eq $index) {
    throw "Catalog index at $IndexPath is empty."
}

# Checked before anything else reads the index: a version this contract does not
# cover makes every field below it a guess, and "the contract moved" is more
# useful than a vocabulary complaint about a field that was renamed.
if ($null -eq $index.PSObject.Properties['schema_version'] -or
    $index.schema_version -ne $SupportedSchemaVersion) {
    $declaredVersion = if ($null -ne $index.PSObject.Properties['schema_version']) { $index.schema_version } else { '<missing>' }
    Add-CatalogError "Catalog index schema_version '$declaredVersion' is not covered by this validator (supports '$SupportedSchemaVersion')."
}

$vocabulary = $null
if ($null -eq $index.PSObject.Properties['vocabulary'] -or $null -eq $index.vocabulary) {
    Add-CatalogError "Catalog index at $IndexPath has no vocabulary block. No artifact tag can be validated without it."
} else {
    $vocabulary = $index.vocabulary
}

# An index with no artifacts key at all is a different fault from one that
# publishes an empty list: the first is a malformed file, the second is a
# catalog that legitimately has nothing to offer yet.
$artifacts = @()
if ($null -eq $index.PSObject.Properties['artifacts']) {
    Add-CatalogError "Catalog index at $IndexPath has no artifacts list. Write an empty list for a catalog with no artifacts."
} elseif ($null -ne $index.artifacts) {
    $artifacts = @($index.artifacts)
}

# Duplicate ids are checked across the whole index because this is the only
# place the whole index is visible. Two ids differing only in case become the
# same directory on Windows and default macOS - the clone succeeds and one
# artifact quietly overwrites the other.
#
# The fold to upper case is explicit rather than left to the hashtable's own
# comparer, which is already case-insensitive. Folding here states which
# filesystem behaviour is being modelled instead of leaning on a property of the
# container, and keeps the key stable if the table is ever swapped.
$seenIds = @{}
for ($i = 0; $i -lt $artifacts.Count; $i++) {
    $artifact = $artifacts[$i]

    # A bare string in the artifacts array answers PSObject.Properties['id'] with
    # nothing, so this also catches "artifacts": ["AS-0001"].
    if ($null -eq $artifact -or
        $artifact -is [string] -or
        $null -eq $artifact.PSObject.Properties['id'] -or
        [string]::IsNullOrWhiteSpace($artifact.id)) {
        Add-CatalogError "Catalog index at $IndexPath contains an artifact with no id (at index $i)."
        continue
    }

    # Upper-cased rather than compared case-insensitively so the message can
    # quote both ids exactly as the catalog wrote them.
    $key = $artifact.id.ToUpperInvariant()
    if ($seenIds.ContainsKey($key)) {
        Add-CatalogError "Catalog index declares '$($seenIds[$key])' and '$($artifact.id)', which collide on a case-insensitive filesystem. Artifact ids must be unique."
        continue
    }

    $seenIds[$key] = $artifact.id
}

for ($i = 0; $i -lt $artifacts.Count; $i++) {
    Test-CatalogArtifact -Artifact $artifacts[$i] -Vocabulary $vocabulary -Index $i
}

return [pscustomobject]@{
    IsValid       = ($errors.Count -eq 0)
    Errors        = $errors.ToArray()
    ArtifactCount = $artifacts.Count
}
