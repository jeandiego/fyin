package sync

import (
	"bytes"
	"encoding/json"
)

// redact remove dados pessoais do payload antes de gravar em `raw`:
// documento, nome, conta e agência de pagador/recebedor, e o CPF, nome e número da conta do titular.
// shortcut: lista fixa de campos vistos nos dados reais (Meu Pluggy, Bradesco); revisar ao conectar outros bancos.
func redact(raw json.RawMessage) (json.RawMessage, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber() // não passa valores monetários por float64
	var doc map[string]any
	if err := dec.Decode(&doc); err != nil {
		return nil, err
	}
	delete(doc, "taxNumber")
	delete(doc, "number")
	delete(doc, "owner") // nome do titular em contas e investimentos
	if pd, ok := doc["paymentData"].(map[string]any); ok {
		for _, side := range []string{"payer", "receiver"} {
			if p, ok := pd[side].(map[string]any); ok {
				for _, k := range []string{"documentNumber", "name", "accountNumber", "branchNumber"} {
					delete(p, k)
				}
			}
		}
	}
	return json.Marshal(doc)
}
