# Entity: SLSA provenance (SLSA Verification step). Only images Harness built
# from an ilmp-* repo on a release branch may deploy.
package ilmp_slsa_provenance

repo_url := object.get(input, ["predicate", "buildDefinition", "externalParameters", "codeMetadata", "repositoryURL"], "")

branch := object.get(input, ["predicate", "buildDefinition", "externalParameters", "codeMetadata", "branch"], "")

builder := object.get(input, ["predicate", "runDetails", "builder", "id"], "")

deny[msg] {
	not regex.match(`github\.com/alexsoto-harness/ilmp-[a-z-]+`, repo_url)
	msg := sprintf("Artifact was not built from an ilmp-* repo (%s)", [repo_url])
}

deny[msg] {
	not startswith(branch, "release/")
	not startswith(branch, "hotfix/")
	msg := sprintf("Artifact was built from branch '%s', not release/* or hotfix/*", [branch])
}

deny[msg] {
	not contains(builder, "harness")
	msg := sprintf("Unexpected builder %s", [builder])
}
