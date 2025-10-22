package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

func helloHandler(w http.ResponseWriter, r *http.Request) {
	// CORS: allow origin and handle preflight
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
	w.Header().Set("Access-Control-Max-Age", "86400")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	// Print request details
	log.Printf("[%s] %s %s - Remote: %s - User-Agent: %s",
		time.Now().Format("2006-01-02 15:04:05"),
		r.Method,
		r.URL.Path,
		r.RemoteAddr,
		r.UserAgent(),
	)

	// Set content type to JSON
	w.Header().Set("Content-Type", "application/json")

	// Create response struct
	response := map[string]interface{}{
		"message":   "Hello world",
		"timestamp": time.Now().Format("2006-01-02 15:04:05"),
		"method":    r.Method,
		"path":      r.URL.Path,
	}

	// Encode and send JSON response
	json.NewEncoder(w).Encode(response)
}

func main() {
	http.HandleFunc("/", helloHandler)
	log.Println("Server starting on port 8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
