Set-StrictMode -Version Latest

# Resolved at file scope rather than in BeforeAll: Pester's discovery pass runs
# before any BeforeAll block, and a path resolved too late leaves the tests
# invoking nothing while still reporting green.
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:ValidatorPath = Join-Path $script:RepoRoot 'scripts/validate-catalog.ps1'

Describe 'validate-catalog.ps1' {
    BeforeAll {
        # Captured from the discovery-time variables above. Pester runs BeforeAll
        # in a fresh scope, so these are re-established here to be visible to
        # every It block below.
        $validator = $PSCommandPath | Split-Path -Parent | Split-Path -Parent |
            Join-Path -ChildPath 'scripts/validate-catalog.ps1'
        $repoRoot = $PSCommandPath | Split-Path -Parent | Split-Path -Parent

        function New-TestIndex {
            <#
                Writes an index.json into $TestDrive and returns its path.

                The defaults describe a valid catalog, so each test below states
                only the single thing it is varying. A test that had to spell out
                a whole index would bury its own subject.
            #>
            param(
                [Parameter(Mandatory)]
                [string] $Name,

                [hashtable] $Vocabulary = @{
                    languages  = @('typescript', 'python')
                    frameworks = @('nestjs')
                    layout     = @('monorepo', 'single')
                    agents     = @('claude-code')
                    topics     = @('code-review', 'testing', 'documentation', 'refactoring')
                },

                [object[]] $Artifacts = @(),

                [string] $SchemaVersion = '1',

                # Set to drop the key entirely rather than write it empty - an
                # index with no artifacts key is a different fault from one
                # publishing an empty list.
                [switch] $OmitArtifacts,

                [switch] $OmitVocabulary
            )

            $index = [ordered]@{
                schema_version = $SchemaVersion
                toolset_ref    = 'refs/tags/v0.1.0'
            }

            if (-not $OmitVocabulary) {
                $index['vocabulary'] = $Vocabulary
            }

            if (-not $OmitArtifacts) {
                $index['artifacts'] = $Artifacts
            }

            $path = Join-Path $TestDrive "$Name.json"
            $index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
            return $path
        }

        function New-RawIndex {
            <#
                Writes literal JSON text. ConvertTo-Json cannot express the shapes
                some tests need - a bare string in the artifacts array, a scalar
                applies_to, "fixture": "false" as a string - because the
                PowerShell value round-trips into something else.
            #>
            param(
                [Parameter(Mandatory)]
                [string] $Name,

                [Parameter(Mandatory)]
                [string] $Json
            )

            $path = Join-Path $TestDrive "$Name.json"
            Set-Content -LiteralPath $path -Value $Json -Encoding utf8NoBOM
            return $path
        }
    }

    Context 'a catalog that should pass' {
        It 'accepts a valid catalog' {
            $path = New-TestIndex -Name 'valid' -Artifacts @(
                @{
                    id = 'AS-0001'; version = '1.0.0'; source_path = 'artifacts/AS-0001'
                    applies_to = @{}; strength = 'always'; topics = @()
                },
                @{
                    id = 'AS-0002'; version = '1.0.0'; source_path = 'artifacts/AS-0002'
                    applies_to = @{ languages = @('typescript'); layout = @('monorepo') }
                    strength = 'on-demand'; topics = @('code-review')
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeTrue
            @($result.Errors).Count | Should -Be 0
            $result.ArtifactCount | Should -Be 2
        }

        It 'accepts an explicitly empty applies_to as universally applicable' {
            # {} is legal and load-bearing: it is how an author says "everywhere"
            # in a way that cannot be confused with having forgotten the field.
            $path = New-TestIndex -Name 'universal' -Artifacts @(
                @{
                    id = 'AS-0003'; version = '1.0.0'; source_path = 'artifacts/AS-0003'
                    applies_to = @{}; strength = 'always'; topics = @()
                }
            )

            (& $validator -IndexPath $path).IsValid | Should -BeTrue
        }

        It 'accepts a catalog that publishes no artifacts yet' {
            $path = New-TestIndex -Name 'empty' -Artifacts @()

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeTrue
            $result.ArtifactCount | Should -Be 0
        }
    }

    Context 'vocabulary agreement' {
        It 'rejects a value outside the vocabulary, naming the artifact and the value' {
            # The silent failure this validator exists for. An artifact tagged
            # with a word nobody publishes matches no profile, installs nothing,
            # and without this check reports nothing either.
            $path = New-TestIndex -Name 'badvalue' -Artifacts @(
                @{
                    id = 'AS-0042'; version = '1.0.0'; source_path = 'artifacts/AS-0042'
                    applies_to = @{ languages = @('cobol') }
                    strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0042'
            $result.Errors | Should -Match 'cobol'
        }

        It 'rejects a value differing from the vocabulary only by case' {
            # 'TypeScript' vs 'typescript'. The installer compares with
            # -ccontains, so a value that differs only in case never matches.
            # Accepting it here would let an artifact pass CI and then install
            # nowhere - exactly the divergence this task exists to close.
            $path = New-TestIndex -Name 'casevalue' -Artifacts @(
                @{
                    id = 'AS-0043'; version = '1.0.0'; source_path = 'artifacts/AS-0043'
                    applies_to = @{ languages = @('TypeScript') }
                    strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0043'
            $result.Errors | Should -Match 'TypeScript'
        }

        It 'rejects a dimension name differing from the contract only by case' {
            # 'Languages' is not 'languages'. The installer walks dimensions with
            # -cnotcontains, so a capitalised key is an unknown dimension there
            # and the tags under it are never read - the artifact silently
            # narrows to nothing.
            $path = New-TestIndex -Name 'casedimension' -Artifacts @(
                @{
                    id = 'AS-0047'; version = '1.0.0'; source_path = 'artifacts/AS-0047'
                    applies_to = @{ Languages = @('typescript') }
                    strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $report = @($result.Errors) -join "`n"
            $report | Should -Match 'AS-0047'
            $report | Should -MatchExactly 'Languages'
        }

        It 'rejects a topic differing from the vocabulary only by case' {
            # Topics decide whether a matched developer actually wants the
            # artifact. A capitalised topic matches no profile's request, so the
            # artifact is selectable in principle and never selected in practice.
            $path = New-TestIndex -Name 'casetopic' -Artifacts @(
                @{
                    id = 'AS-0048'; version = '1.0.0'; source_path = 'artifacts/AS-0048'
                    applies_to = @{}; strength = 'on-demand'; topics = @('Code-Review')
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $report = @($result.Errors) -join "`n"
            $report | Should -Match 'AS-0048'
            $report | Should -MatchExactly 'Code-Review'
        }

        It 'rejects a topic outside the vocabulary, naming the artifact and the topic' {
            $path = New-TestIndex -Name 'badtopic' -Artifacts @(
                @{
                    id = 'AS-0044'; version = '1.0.0'; source_path = 'artifacts/AS-0044'
                    applies_to = @{}; strength = 'on-demand'; topics = @('perfomance')
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0044'
            $result.Errors | Should -Match 'perfomance'
        }

        It 'rejects a dimension outside the five the installer knows' {
            # The installer filters on exactly five dimensions. A sixth is not a
            # narrower artifact - it is a dimension nothing reads.
            $path = New-TestIndex -Name 'baddimension' -Artifacts @(
                @{
                    id = 'AS-0045'; version = '1.0.0'; source_path = 'artifacts/AS-0045'
                    applies_to = @{ databases = @('postgres') }
                    strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0045'
            $result.Errors | Should -Match 'databases'
        }

        It 'rejects a dimension the vocabulary does not publish, blaming the vocabulary' {
            # 'layout' is a known dimension, so the artifact is not at fault; the
            # vocabulary omitting it is. Reporting this as merely "value not
            # allowed" would send the author hunting in the wrong file.
            $path = New-TestIndex -Name 'vocabgap' -Vocabulary @{
                languages  = @('typescript')
                frameworks = @('nestjs')
                agents     = @('claude-code')
                topics     = @('code-review')
            } -Artifacts @(
                @{
                    id = 'AS-0046'; version = '1.0.0'; source_path = 'artifacts/AS-0046'
                    applies_to = @{ layout = @('monorepo') }
                    strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0046'
            $result.Errors | Should -Match 'layout'
            $result.Errors | Should -Match 'vocabulary'
        }
    }

    Context 'required fields' {
        It 'rejects a missing applies_to, naming the artifact' {
            # Absent is not the same as {}. Requiring it explicitly means "applies
            # everywhere" can never be confused with "the author forgot".
            $path = New-TestIndex -Name 'noappliesto' -Artifacts @(
                @{
                    id = 'AS-0050'; version = '1.0.0'; source_path = 'artifacts/AS-0050'
                    strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0050'
            $result.Errors | Should -Match 'applies_to'
        }

        It 'rejects a missing strength, naming the artifact' {
            $path = New-TestIndex -Name 'nostrength' -Artifacts @(
                @{
                    id = 'AS-0051'; version = '1.0.0'; source_path = 'artifacts/AS-0051'
                    applies_to = @{}; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0051'
            $result.Errors | Should -Match 'strength'
        }

        It 'rejects a strength that is neither always nor on-demand' {
            $path = New-TestIndex -Name 'badstrength' -Artifacts @(
                @{
                    id = 'AS-0052'; version = '1.0.0'; source_path = 'artifacts/AS-0052'
                    applies_to = @{}; strength = 'sometimes'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0052'
            $result.Errors | Should -Match 'sometimes'
        }

        It 'rejects an on-demand artifact with no topics, naming the artifact' {
            # No profile can ever select it, so it is dead catalog content rather
            # than an artifact that merely happens not to match today.
            $path = New-TestIndex -Name 'ondemandnotopics' -Artifacts @(
                @{
                    id = 'AS-0053'; version = '1.0.0'; source_path = 'artifacts/AS-0053'
                    applies_to = @{ languages = @('typescript') }
                    strength = 'on-demand'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0053'
            $result.Errors | Should -Match 'on-demand'
        }

        It 'rejects an on-demand artifact whose topics key is absent entirely' {
            $path = New-TestIndex -Name 'ondemandnotopicskey' -Artifacts @(
                @{
                    id = 'AS-0054'; version = '1.0.0'; source_path = 'artifacts/AS-0054'
                    applies_to = @{}; strength = 'on-demand'
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0054'
        }

        It 'rejects applies_to written as a scalar rather than an object' {
            # A scalar has no properties to walk, so a validator that only looped
            # would pass it silently - and the installer would then treat the
            # artifact as applying everywhere.
            $path = New-RawIndex -Name 'scalarappliesto' -Json @'
{
  "schema_version": "1",
  "toolset_ref": "refs/tags/v0.1.0",
  "vocabulary": { "languages": ["typescript"], "frameworks": [], "layout": [], "agents": [], "topics": [] },
  "artifacts": [
    { "id": "AS-0055", "version": "1.0.0", "source_path": "artifacts/AS-0055", "applies_to": "typescript", "strength": "always", "topics": [] }
  ]
}
'@

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0055'
            $result.Errors | Should -Match 'applies_to'
        }
    }

    Context 'the fixture escape hatch' {
        It 'exempts a legitimate AS-SPIKE-* fixture' {
            # Transport test data, not catalog content: it carries no applies_to
            # or strength at all and must still pass.
            $path = New-TestIndex -Name 'goodfixture' -Artifacts @(
                @{
                    id = 'AS-SPIKE-042'; version = '0.0.1'
                    source_path = 'artifacts/AS-SPIKE-042'; fixture = $true
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeTrue
            $result.ArtifactCount | Should -Be 1
        }

        It 'rejects a non-AS-SPIKE id claiming fixture: true, naming the id' {
            # The flag suppresses every other check, so a typo'd fixture:true on a
            # real artifact would hide it from every install with no error at all.
            $path = New-TestIndex -Name 'badfixture' -Artifacts @(
                @{
                    id = 'AS-0100'; version = '1.0.0'
                    source_path = 'artifacts/AS-0100'; fixture = $true
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0100'
            $result.Errors | Should -Match 'fixture'
        }

        It 'does not treat the string "false" as a fixture flag' {
            # The string 'false' is truthy in PowerShell. A truthiness test here
            # would exempt this artifact and hide it from every install; the flag
            # must be compared with -eq $true. The artifact below is otherwise
            # invalid - on-demand with no topics - so being validated normally is
            # observable as an error, and being exempted is observable as a pass.
            $path = New-RawIndex -Name 'stringfalsefixture' -Json @'
{
  "schema_version": "1",
  "toolset_ref": "refs/tags/v0.1.0",
  "vocabulary": { "languages": ["typescript"], "frameworks": [], "layout": [], "agents": [], "topics": ["testing"] },
  "artifacts": [
    { "id": "AS-SPIKE-077", "version": "1.0.0", "source_path": "artifacts/AS-SPIKE-077", "fixture": "false", "applies_to": {}, "strength": "on-demand", "topics": [] }
  ]
}
'@

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-SPIKE-077'
        }

        It 'treats the string "true" as a fixture flag, matching the installer' {
            # Documenting a known divergence from JSON's own types rather than
            # asserting a preference. PowerShell coerces the string 'true' to
            # $true, so "fixture": "true" satisfies -eq $true and exempts the
            # artifact - here and in the installer alike, since both express the
            # same test.
            #
            # This is pinned rather than tightened deliberately. The rule that
            # matters is that the two sides agree: a validator stricter than the
            # installer fails an artifact in CI that would have installed
            # perfectly well. The asymmetric case is the dangerous one and is
            # covered above - 'false' must never exempt, because that hides a
            # real artifact from every install. Exempting on 'true' only affects
            # artifacts already claiming to be fixtures, and the AS-SPIKE-*
            # id restriction still bounds who may claim it.
            $path = New-RawIndex -Name 'stringtruefixture' -Json @'
{
  "schema_version": "1",
  "toolset_ref": "refs/tags/v0.1.0",
  "vocabulary": { "languages": ["typescript"], "frameworks": [], "layout": [], "agents": [], "topics": ["testing"] },
  "artifacts": [
    { "id": "AS-SPIKE-078", "version": "1.0.0", "source_path": "artifacts/AS-SPIKE-078", "fixture": "true" }
  ]
}
'@

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeTrue
        }

        It 'still bounds who may claim a string "true" fixture flag' {
            # The coercion above must not become a bypass: a non-AS-SPIKE id
            # claiming "fixture": "true" is still rejected, so the flag cannot
            # hide a real artifact however it is spelled.
            $path = New-RawIndex -Name 'stringtruenonspike' -Json @'
{
  "schema_version": "1",
  "toolset_ref": "refs/tags/v0.1.0",
  "vocabulary": { "languages": ["typescript"], "frameworks": [], "layout": [], "agents": [], "topics": ["testing"] },
  "artifacts": [
    { "id": "AS-0079", "version": "1.0.0", "source_path": "artifacts/AS-0079", "fixture": "true" }
  ]
}
'@

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0079'
        }
    }

    Context 'index-level structure' {
        It 'rejects ids colliding case-insensitively, naming both' {
            # AS-0001 and as-0001 are the same directory on Windows and default
            # macOS: the clone succeeds and one artifact quietly overwrites the
            # other.
            $path = New-TestIndex -Name 'idcollision' -Artifacts @(
                @{
                    id = 'AS-0001'; version = '1.0.0'; source_path = 'artifacts/AS-0001'
                    applies_to = @{}; strength = 'always'; topics = @()
                },
                @{
                    id = 'as-0001'; version = '1.0.0'; source_path = 'artifacts/as-0001'
                    applies_to = @{}; strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse

            # Case-sensitive match, or 'as-0001' would be satisfied by the
            # 'AS-0001' already in the message and the test would pass without
            # the second id ever being quoted.
            $report = @($result.Errors) -join "`n"
            $report | Should -MatchExactly 'AS-0001'
            $report | Should -MatchExactly 'as-0001'
        }

        It 'rejects exactly duplicated ids' {
            $path = New-TestIndex -Name 'idduplicate' -Artifacts @(
                @{
                    id = 'AS-0002'; version = '1.0.0'; source_path = 'artifacts/AS-0002'
                    applies_to = @{}; strength = 'always'; topics = @()
                },
                @{
                    id = 'AS-0002'; version = '2.0.0'; source_path = 'artifacts/AS-0002'
                    applies_to = @{}; strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'AS-0002'
        }

        It 'rejects an artifact with no id, naming its position' {
            # There is no id to name, so the position is the only handle the
            # author has. An error naming nothing would be unactionable.
            $path = New-TestIndex -Name 'noid' -Artifacts @(
                @{
                    version = '1.0.0'; source_path = 'artifacts/AS-0003'
                    applies_to = @{}; strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse

            # Asserts the index-level id sweep specifically, not merely that some
            # message mentions position 0. The per-artifact checks label an
            # id-less artifact '<artifact at index 0>', so a looser assertion
            # passes on that fallback even when the id sweep is gone entirely.
            $report = @($result.Errors) -join "`n"
            $report | Should -Match 'artifact with no id \(at index 0\)'
        }

        It 'rejects a bare string in the artifacts array' {
            $path = New-RawIndex -Name 'barestring' -Json @'
{
  "schema_version": "1",
  "toolset_ref": "refs/tags/v0.1.0",
  "vocabulary": { "languages": [], "frameworks": [], "layout": [], "agents": [], "topics": [] },
  "artifacts": ["AS-0004"]
}
'@

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse

            $report = @($result.Errors) -join "`n"
            $report | Should -Match 'artifact with no id \(at index 0\)'
            $report | Should -Match 'is not an object'
        }

        It 'rejects an index with no artifacts key at all' {
            # Distinct from an empty list: this is a malformed file, not a catalog
            # that legitimately has nothing to offer yet.
            $path = New-TestIndex -Name 'noartifactskey' -OmitArtifacts

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'artifacts'
        }

        It 'rejects an index with no vocabulary block' {
            $path = New-TestIndex -Name 'novocabulary' -OmitVocabulary -Artifacts @(
                @{
                    id = 'AS-0005'; version = '1.0.0'; source_path = 'artifacts/AS-0005'
                    applies_to = @{}; strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'vocabulary'
        }

        It 'rejects a schema_version this contract does not cover' {
            $path = New-TestIndex -Name 'futureschema' -SchemaVersion '2'

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Match 'schema_version'
        }
    }

    Context 'reporting every fault at once' {
        It 'reports every error rather than stopping at the first' {
            # Unlike the installer, which throws on the first problem because it
            # must not proceed, CI has no reason to stop. An author fixing one
            # typo per push is a bad enough experience that they stop trusting
            # the check.
            $path = New-TestIndex -Name 'twofaults' -Artifacts @(
                @{
                    id = 'AS-0060'; version = '1.0.0'; source_path = 'artifacts/AS-0060'
                    applies_to = @{ languages = @('cobol') }
                    strength = 'always'; topics = @()
                },
                @{
                    id = 'AS-0061'; version = '1.0.0'; source_path = 'artifacts/AS-0061'
                    applies_to = @{ languages = @('typescript') }
                    strength = 'on-demand'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            @($result.Errors).Count | Should -BeGreaterOrEqual 2

            # Joined rather than piped: piping an array to Should -Match asserts
            # that *every* element matches, which is not the claim here. Each id
            # must appear somewhere in the report, not in every line of it.
            $report = @($result.Errors) -join "`n"
            $report | Should -Match 'AS-0060'
            $report | Should -Match 'AS-0061'
        }

        It 'reports every fault within a single artifact' {
            # One artifact, two independent problems. Stopping at the first would
            # hide the second behind another CI round-trip.
            $path = New-TestIndex -Name 'twofaultsoneartifact' -Artifacts @(
                @{
                    id = 'AS-0062'; version = '1.0.0'; source_path = 'artifacts/AS-0062'
                    applies_to = @{ languages = @('cobol') }
                    strength = 'on-demand'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            @($result.Errors).Count | Should -BeGreaterOrEqual 2
        }

        It 'names an artifact in every error it reports' {
            # A message naming nothing is unactionable in CI, where the author
            # cannot poke at the object. Every error must carry either an id or a
            # position.
            $path = New-TestIndex -Name 'allnamed' -Artifacts @(
                @{
                    id = 'AS-0063'; version = '1.0.0'; source_path = 'artifacts/AS-0063'
                    applies_to = @{ languages = @('cobol') }
                    strength = 'sometimes'
                },
                @{
                    version = '1.0.0'; source_path = 'artifacts/unnamed'
                    applies_to = @{}; strength = 'always'; topics = @()
                }
            )

            $result = & $validator -IndexPath $path

            $result.IsValid | Should -BeFalse
            foreach ($message in @($result.Errors)) {
                $message | Should -Match '(AS-[A-Za-z0-9-]+|index \d+)'
            }
        }
    }

    Context 'a broken invocation rather than broken catalog content' {
        It 'throws naming the path when the index file is missing' {
            $missing = Join-Path $TestDrive 'nosuchfile.json'

            { & $validator -IndexPath $missing } | Should -Throw "*nosuchfile.json*"
        }

        It 'throws naming the path when the index is not valid JSON' {
            # ConvertFrom-Json quotes the offending token but never the file, and
            # a catalog can hold many index files across many refs.
            $path = New-RawIndex -Name 'malformed' -Json '{ "schema_version": "1", '

            { & $validator -IndexPath $path } | Should -Throw "*malformed.json*"
        }
    }

    Context 'the catalog in this repository' {
        It 'validates the real index.json' {
            # The check that makes the other tests worth anything: the rules above
            # are only the contract if the shipped catalog actually satisfies them.
            $result = & $validator -IndexPath (Join-Path $repoRoot 'index.json')

            $result.Errors | Should -Be @()
            $result.IsValid | Should -BeTrue

            # Counted from the file rather than pinned to a literal: the catalog
            # grows as artifacts are published, and a hardcoded total turns every
            # such addition into an unrelated test failure. What is worth asserting
            # is that the validator saw every entry, not how many there are.
            $indexed = @((Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'index.json') |
                ConvertFrom-Json).artifacts).Count
            $result.ArtifactCount | Should -Be $indexed
        }
    }
}
