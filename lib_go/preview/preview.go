package main

import "C"
import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"golang.org/x/text/encoding/japanese"
	"golang.org/x/text/transform"
)

const (
	BinaryThreshold    = 0.3
	DefaultMaxLines    = 50
	MaxLineLength      = 500
	BinarySampleSize   = 512
	MaxPreviewFileSize = 10 * 1024 * 1024 // 10MB
)

// PreviewResult represents the result of file preview generation
type PreviewResult struct {
	Type      string   `json:"type"`
	Language  string   `json:"language,omitempty"`
	Lines     []string `json:"lines"`
	Truncated bool     `json:"truncated"`
	Size      int64    `json:"size"`
	Mtime     int64    `json:"mtime"`
	Encoding  string   `json:"encoding"`
	Message   string   `json:"message,omitempty"`
	Error     string   `json:"error,omitempty"`
}

//export GeneratePreview
func GeneratePreview(path *C.char, maxLines C.int) *C.char {
	goPath := C.GoString(path)
	max := int(maxLines)
	if max <= 0 {
		max = DefaultMaxLines
	}

	result := generatePreview(goPath, max)
	jsonBytes, _ := json.Marshal(result)
	return C.CString(string(jsonBytes))
}

//export IsBinaryFile
func IsBinaryFile(path *C.char) C.int {
	goPath := C.GoString(path)
	if isBinaryFile(goPath) {
		return 1
	}
	return 0
}

func generatePreview(path string, maxLines int) PreviewResult {
	info, err := os.Stat(path)
	if err != nil {
		return PreviewResult{
			Type:  "error",
			Error: "File not found or not accessible",
			Lines: []string{"Error: File not found"},
		}
	}

	size := info.Size()
	mtime := info.ModTime().Unix()

	if size == 0 {
		return PreviewResult{
			Type:     "empty",
			Lines:    []string{},
			Size:     0,
			Mtime:    mtime,
			Encoding: "UTF-8",
		}
	}

	if size > MaxPreviewFileSize {
		return PreviewResult{
			Type:    "error",
			Message: "File too large for preview",
			Lines:   []string{"[File too large - preview not available]"},
			Size:    size,
			Mtime:   mtime,
		}
	}

	if isBinaryFile(path) {
		fileType := determineFileType(path)
		return PreviewResult{
			Type:     "binary",
			Language: fileType.Language,
			Message:  "Binary file - cannot preview",
			Lines:    []string{"[Binary file]"},
			Size:     size,
			Mtime:    mtime,
			Encoding: "binary",
		}
	}

	lines, truncated, encoding := readTextFile(path, maxLines)
	fileType := determineFileType(path)

	return PreviewResult{
		Type:      fileType.Type,
		Language:  fileType.Language,
		Lines:     lines,
		Truncated: truncated,
		Size:      size,
		Mtime:     mtime,
		Encoding:  encoding,
	}
}

func isBinaryFile(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return true
	}
	defer file.Close()

	sample := make([]byte, BinarySampleSize)
	n, err := file.Read(sample)
	if err != nil && err != io.EOF {
		return true
	}
	sample = sample[:n]

	if len(sample) == 0 {
		return false
	}

	binaryCount := 0
	for _, b := range sample {
		if b < 32 && b != 9 && b != 10 && b != 13 {
			binaryCount++
		}
	}

	ratio := float64(binaryCount) / float64(len(sample))
	return ratio > BinaryThreshold
}

func readTextFile(path string, maxLines int) ([]string, bool, string) {
	lines, truncated := readUTF8File(path, maxLines)
	if len(lines) > 0 {
		return lines, truncated, "UTF-8"
	}

	lines, truncated = readShiftJISFile(path, maxLines)
	if len(lines) > 0 {
		return lines, truncated, "Shift_JIS"
	}

	return []string{"[Encoding error - cannot read file]"}, false, "unknown"
}

func readUTF8File(path string, maxLines int) ([]string, bool) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}

	if !utf8.Valid(content) {
		return nil, false
	}

	return splitLines(string(content), maxLines)
}

func readShiftJISFile(path string, maxLines int) ([]string, bool) {
	file, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer file.Close()

	decoder := japanese.ShiftJIS.NewDecoder()
	reader := transform.NewReader(file, decoder)

	content, err := io.ReadAll(reader)
	if err != nil {
		return nil, false
	}

	return splitLines(string(content), maxLines)
}

func splitLines(content string, maxLines int) ([]string, bool) {
	var lines []string
	truncated := false

	reader := strings.NewReader(content)
	lineCount := 0

	for {
		if lineCount >= maxLines {
			truncated = true
			break
		}

		line, err := readLine(reader)
		if err == io.EOF {
			if line != "" {
				lines = append(lines, truncateLine(line))
			}
			break
		}
		if err != nil {
			break
		}

		lines = append(lines, truncateLine(line))
		lineCount++
	}

	return lines, truncated
}

func readLine(reader *strings.Reader) (string, error) {
	var line bytes.Buffer
	for {
		b, err := reader.ReadByte()
		if err != nil {
			return line.String(), err
		}
		if b == '\n' {
			return line.String(), nil
		}
		if b != '\r' {
			line.WriteByte(b)
		}
	}
}

func truncateLine(line string) string {
	if len(line) <= MaxLineLength {
		return line
	}
	return line[:MaxLineLength] + "..."
}

type FileType struct {
	Type     string
	Language string
}

func determineFileType(path string) FileType {
	ext := strings.ToLower(filepath.Ext(path))

	switch ext {
	case ".rb":
		return FileType{Type: "code", Language: "ruby"}
	case ".py":
		return FileType{Type: "code", Language: "python"}
	case ".js", ".mjs":
		return FileType{Type: "code", Language: "javascript"}
	case ".ts":
		return FileType{Type: "code", Language: "typescript"}
	case ".go":
		return FileType{Type: "code", Language: "go"}
	case ".rs":
		return FileType{Type: "code", Language: "rust"}
	case ".c", ".h":
		return FileType{Type: "code", Language: "c"}
	case ".cpp", ".cc", ".hpp":
		return FileType{Type: "code", Language: "cpp"}
	case ".html", ".htm":
		return FileType{Type: "code", Language: "html"}
	case ".css":
		return FileType{Type: "code", Language: "css"}
	case ".json":
		return FileType{Type: "code", Language: "json"}
	case ".yml", ".yaml":
		return FileType{Type: "code", Language: "yaml"}
	case ".md", ".markdown":
		return FileType{Type: "code", Language: "markdown"}
	case ".txt", ".log":
		return FileType{Type: "text", Language: ""}
	default:
		return FileType{Type: "text", Language: ""}
	}
}

func main() {}
