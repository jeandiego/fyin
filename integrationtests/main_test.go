package integrationtests

import (
	"testing"

	"fyin/internal/testdb"
)

func TestMain(m *testing.M) { testdb.Main(m) }
