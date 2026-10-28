// Package migrations expõe os .sql embutidos, aplicados em ordem de nome.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
