# Entity: SBOM (SBOM Policy Enforcement in the build stage).
# Input: list of packages {packageName, packageVersion, packageLicense}.
package ilmp_sbom_denylist

denied_packages := {
	"pyyaml": {"5.3", "5.3.1"},
	"log4j-core": {"2.14.1", "2.15.0"},
}

denied_licenses := {"GPL-3.0", "GPL-3.0-only", "AGPL-3.0", "AGPL-3.0-only"}

deny[msg] {
	pkg := input[_]
	versions := denied_packages[lower(pkg.packageName)]
	versions[pkg.packageVersion]
	msg := sprintf("Denied package %s %s", [pkg.packageName, pkg.packageVersion])
}

deny[msg] {
	pkg := input[_]
	lic := pkg.packageLicense[_]
	denied_licenses[lic]
	msg := sprintf("Denied license %s on %s", [lic, pkg.packageName])
}
