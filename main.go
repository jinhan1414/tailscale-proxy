package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"time"
)

//go:embed web/index.html
var webFS embed.FS

var startTime = time.Now()

type uptimeData struct {
	Formatted string
	Seconds   int64
	StartedAt string
}

// formatUptime 将时长格式化为 "X天 X小时 X分钟 X秒" 形式（省略为零的高位单位）。
func formatUptime(d time.Duration) string {
	total := int64(d / time.Second)
	days := total / 86400
	hours := (total % 86400) / 3600
	minutes := (total % 3600) / 60
	seconds := total % 60
	switch {
	case days > 0:
		return fmt.Sprintf("%d天 %d小时 %d分钟 %d秒", days, hours, minutes, seconds)
	case hours > 0:
		return fmt.Sprintf("%d小时 %d分钟 %d秒", hours, minutes, seconds)
	case minutes > 0:
		return fmt.Sprintf("%d分钟 %d秒", minutes, seconds)
	default:
		return fmt.Sprintf("%d秒", seconds)
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	tmpl, err := template.ParseFS(webFS, "web/index.html")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	d := time.Since(startTime)
	data := uptimeData{
		Formatted: formatUptime(d),
		Seconds:   int64(d / time.Second),
		StartedAt: startTime.Format(time.RFC3339),
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.Execute(w, data); err != nil {
		log.Printf("template execute error: %v", err)
	}
}

func uptimeAPIHandler(w http.ResponseWriter, r *http.Request) {
	d := time.Since(startTime)
	resp := map[string]any{
		"uptime_seconds": int64(d / time.Second),
		"started_at":     startTime.Format(time.RFC3339),
		"formatted":      formatUptime(d),
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("json encode error: %v", err)
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", indexHandler)
	mux.HandleFunc("/api/uptime", uptimeAPIHandler)

	log.Printf("status-server listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
