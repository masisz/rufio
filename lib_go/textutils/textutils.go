package main

import "C"
import (
	"encoding/json"

	"github.com/mattn/go-runewidth"
)

//export DisplayWidth
func DisplayWidth(text *C.char) C.int {
	goText := C.GoString(text)
	return C.int(runewidth.StringWidth(goText))
}

//export TruncateToWidth
func TruncateToWidth(text *C.char, maxWidth C.int) *C.char {
	goText := C.GoString(text)
	width := int(maxWidth)

	truncated := runewidth.Truncate(goText, width, "...")
	return C.CString(truncated)
}

//export WrapText
func WrapText(text *C.char, maxWidth C.int) *C.char {
	goText := C.GoString(text)
	width := int(maxWidth)

	lines := wrapTextToWidth(goText, width)
	jsonBytes, _ := json.Marshal(lines)
	return C.CString(string(jsonBytes))
}

//export CalculateWidths
func CalculateWidths(lines *C.char) *C.char {
	goLines := C.GoString(lines)

	var lineArray []string
	json.Unmarshal([]byte(goLines), &lineArray)

	widths := make([]int, len(lineArray))
	for i, line := range lineArray {
		widths[i] = runewidth.StringWidth(line)
	}

	jsonBytes, _ := json.Marshal(widths)
	return C.CString(string(jsonBytes))
}

func wrapTextToWidth(text string, maxWidth int) []string {
	var lines []string
	var currentLine string
	currentWidth := 0

	for _, r := range text {
		charWidth := runewidth.RuneWidth(r)

		if currentWidth+charWidth > maxWidth {
			if currentLine != "" {
				lines = append(lines, currentLine)
			}
			currentLine = string(r)
			currentWidth = charWidth
		} else {
			currentLine += string(r)
			currentWidth += charWidth
		}
	}

	if currentLine != "" {
		lines = append(lines, currentLine)
	}

	return lines
}

func main() {}
