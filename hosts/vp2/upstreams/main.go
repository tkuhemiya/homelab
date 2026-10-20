// Command upstreams prints CLIProxyAPI's `api-keys:` config section, with model
// lists fetched live from each provider.
//
// Providers come from the JSON file given as the only argument. A provider is
// included only when its key's environment variable is set, so run this under
// `doppler run --`.
//
//   - gemini: CLIProxyAPI knows Gemini's models itself; only the key is needed.
//   - openai-compatibility: CLIProxyAPI routes only models listed in its config, so
//     this asks the provider's /models endpoint and lists every model that matches
//     `include` and doesn't match `exclude` (both regexes, optional). Clients call
//     a short alias: "nvidia/nemotron-3-super-120b-a12b:free" -> "nemotron-3-super-120b-a12b".
//
// Exits non-zero if an enabled provider can't be reached, so a network blip never
// replaces a working config with one that has no models.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
	"time"
)

type provider struct {
	Name    string `json:"name"`
	Type    string `json:"type"`
	BaseURL string `json:"base_url"`
	KeyEnv  string `json:"key_env"`
	Include string `json:"include"`
	Exclude string `json:"exclude"`
}

var client = &http.Client{Timeout: 30 * time.Second}

func fetchModels(baseURL, key string) ([]string, error) {
	req, err := http.NewRequest("GET", strings.TrimSuffix(baseURL, "/")+"/models", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	// Groq's edge rejects some default client user agents with a 403.
	req.Header.Set("User-Agent", "homelab-cli-proxy-api/1")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %s", resp.Status)
	}
	var body struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(body.Data))
	for _, m := range body.Data {
		ids = append(ids, m.ID)
	}
	slices.Sort(ids)
	return ids, nil
}

func alias(id string) string {
	return strings.TrimSuffix(id[strings.LastIndex(id, "/")+1:], ":free")
}

// q quotes s as a YAML string (a JSON string is a valid YAML string).
func q(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func main() {
	log.SetFlags(0)
	if len(os.Args) != 2 {
		log.Fatal("usage: upstreams PROVIDERS.json")
	}
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	var providers []provider
	if err := json.Unmarshal(raw, &providers); err != nil {
		log.Fatalf("%s: %v", os.Args[1], err)
	}

	var gemini, compat []string
	for _, p := range providers {
		key := os.Getenv(p.KeyEnv)
		if key == "" {
			continue
		}
		if p.Type == "gemini" {
			gemini = append(gemini,
				"    - name: "+q(p.Name),
				"      keys:",
				"        - api-key: "+q(key))
			continue
		}

		include, err := regexp.Compile(p.Include)
		if err != nil {
			log.Fatalf("%s: include: %v", p.Name, err)
		}
		exclude, err := regexp.Compile(p.Exclude)
		if err != nil {
			log.Fatalf("%s: exclude: %v", p.Name, err)
		}
		all, err := fetchModels(p.BaseURL, key)
		if err != nil {
			log.Fatalf("%s: can't list models at %s: %v", p.Name, p.BaseURL, err)
		}
		var ids []string
		for _, id := range all {
			if include.MatchString(id) && (p.Exclude == "" || !exclude.MatchString(id)) {
				ids = append(ids, id)
			}
		}
		if len(ids) == 0 {
			log.Printf("%s: no models match the filter, skipping", p.Name)
			continue
		}

		compat = append(compat,
			"    - name: "+q(p.Name),
			"      base-url: "+q(p.BaseURL),
			"      keys:",
			"        - api-key: "+q(key),
			"      models:")
		for _, id := range ids {
			compat = append(compat, "        - name: "+q(id), "          alias: "+q(alias(id)))
		}
		log.Printf("%s: %d models", p.Name, len(ids))
	}

	if len(gemini) == 0 && len(compat) == 0 {
		return
	}
	fmt.Println("api-keys:")
	if len(gemini) > 0 {
		fmt.Println("  gemini:\n" + strings.Join(gemini, "\n"))
	}
	if len(compat) > 0 {
		fmt.Println("  openai-compatibility:\n" + strings.Join(compat, "\n"))
	}
}
