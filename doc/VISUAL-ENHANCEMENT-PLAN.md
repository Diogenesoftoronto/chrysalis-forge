# Visual Enhancement Plan for Chrysalis Forge

## Implementation Status

> **Last Updated**: January 2026
>
> **Phase 1-2 COMPLETE** ✓ - Core visual modules implemented

### Completed Modules

| Module | Status | File |
|--------|--------|------|
| Terminal Styling System | ✅ Complete | `src/utils/terminal-style.rkt` |
| Loading Animations | ✅ Complete | `src/utils/loading-animations.rkt` |
| Message Boxes | ✅ Complete | `src/utils/message-boxes.rkt` |
| Tool Visualization | ✅ Complete | `src/utils/tool-visualization.rkt` |
| Stream Effects | ✅ Complete | `src/utils/stream-effects.rkt` |
| Intro Animation | ✅ Complete | `src/utils/intro-animation.rkt` |
| Status Bar | ✅ Complete | `src/utils/status-bar.rkt` |
| Session Summary Viz | ✅ Complete | `src/utils/session-summary-viz.rkt` |
| Theme Manager (CLI) | ✅ Complete | `src/utils/theme-manager.rkt` |
| Theme System (GUI) | ✅ Complete | `src/gui/theme-system.rkt` |
| Chat Widget | ✅ Complete | `src/gui/chat-widget.rkt` |
| Widget Framework | ✅ Complete | `src/gui/widget-framework.rkt` |
| Notification System | ✅ Complete | `src/gui/notification-system.rkt` |
| Animation Engine | ✅ Complete | `src/gui/animation-engine.rkt` |

### Remaining Work

- [ ] Integration with main.rkt CLI
- [ ] Integration with main-gui.rkt
- [ ] TUI interactive components
- [ ] Icon library for GUI
- [ ] Session manager dialog
- [ ] Workflow editor
- [ ] Settings dialog with live preview
- [ ] Accessibility features

---

## Executive Summary

This document outlines a comprehensive plan to enhance the visual appeal, interactivity, and user experience of **both** Chrysalis Forge CLI (`--interactive` mode) and GUI (`--gui` mode). The goal is to transform the already-functional interfaces into beautiful, animated, and delightful experiences that stand out in both CLI and GUI tool landscapes.

## Table of Contents

1. [Goals and Objectives](#goals-and-objectives)
2. [Current State Analysis](#current-state-analysis)
3. [CLI Feature Breakdown](#cli-feature-breakdown)
4. [GUI Feature Breakdown](#gui-feature-breakdown)
5. [Implementation Phases](#implementation-phases)
6. [Technical Specifications](#technical-specifications)
7. [Code Architecture](#code-architecture)
8. [Testing Strategy](#testing-strategy)
9. [Milestones and Timeline](#milestones-and-timeline)
10. [Resources and Dependencies](#resources-and-dependencies)
11. [Success Metrics](#success-metrics)

---

## Goals and Objectives

### Primary Goals

1. **Enhance Visual Appeal**: Create visually stunning CLI and GUI interfaces that users enjoy interacting with
2. **Improve User Experience**: Provide clear feedback, reduce perceived wait times, and make complex operations feel simple
3. **Increase Engagement**: Make both interfaces memorable and delightful through animations and polish
4. **Maintain Performance**: Ensure all visual enhancements are performant and don't impact core functionality
5. **Preserve Accessibility**: Keep both CLI and GUI usable on diverse hardware and configurations

### Secondary Objectives

- Establish a consistent visual identity for Chrysalis Forge across CLI and GUI
- Create reusable styling components for future features
- Set a high bar for open-source CLI and GUI tools
- Enable easy customization via environment variables or config files

---

## Current State Analysis

### Existing CLI Visual Elements

The CLI already includes:
- **Figlet Banner**: ASCII art logo on startup (line 1159, main.rkt)
- **Basic Spinner**: Simple animated spinner in `src/utils/utils-spinner.rkt`
- **Raw Terminal Support**: Bracketed paste mode and special key handling (main.rkt:1025-1136)
- **Session Summary**: Basic text-based statistics display (main.rkt:950-1022)

### Existing GUI Elements

The GUI (main-gui.rkt) currently provides:
- **Basic Frame Layout**: 900x700 window with toolbar, chat area, and input
- **Simple Color Scheme**: Hardcoded dark colors (bg-color, fg-color, accent-color)
- **Standard Widgets**: Basic Racket GUI widgets (choice%, button%, text-field%)
- **Chat Display**: Plain text editor with simple role headers (USER/ASSISTANT/SYSTEM)
- **Basic Dialogs**: Session chooser, configuration, workflows dialogs
- **Toolbar**: Model/mode/priority selectors with standard dropdown styling
- **Status Bar**: Simple text labels for cost and tokens

### Areas for Improvement - CLI

1. **No Color System**: All output is plain text
2. **Limited Animations**: Only one basic spinner exists
3. **Inconsistent Output**: Different modules use different formatting styles
4. **No Visual Hierarchy**: Important messages don't stand out
5. **Static Content**: Everything is text-based with no dynamic visual feedback
6. **Error Display**: Plain error messages without visual framing
7. **Tool Execution**: No visual feedback during tool calls

### Areas for Improvement - GUI

1. **Outdated Design**: Standard Racket widgets look dated (Windows 95 style)
2. **No Animations**: Loading states, transitions, and feedback are absent
3. **Limited Customization**: Hardcoded colors, no theme support
4. **Plain Chat**: Message bubbles lack styling, syntax highlighting, or visual distinction
5. **Basic Layout**: No responsive design, poor spacing, lacks modern UI patterns
6. **No Icons**: Pure text labels throughout
7. **Minimal Feedback**: No loading indicators, progress bars, or success animations
8. **Streaming Visualization**: LLM responses appear all at once instead of streaming
9. **No Notifications**: No toast messages or alerts
10. **Accessibility**: No dark/light mode, poor contrast options

---

## CLI Feature Breakdown

### 1. Terminal Styling System

**Priority**: High
**Effort**: 2-3 hours

Create a comprehensive styling library that provides:
- ANSI color codes for standard colors (red, green, blue, yellow, etc.)
- Bright color variants for better visibility
- Text formatting (bold, dim, underline, blink)
- Text effects (rainbow, gradient)
- Safe fallback for terminals without color support
- Theme presets (light, dark, cyberpunk, minimal)

**File**: `src/utils/terminal-style.rkt`

**API Design**:
```racket
(color 'cyan "text")           ; Colored text
(bold "important")             ; Bold text
(dim "secondary")              ; Dimmed text
(underline "link")             ; Underlined text
(rainbow "fun text")           ; Rainbow text
(error-message "oops")         ; Pre-styled error
(success-message "done")       ; Pre-styled success
(warning-message "caution")    ; Pre-styled warning
(info-message "note")          ; Pre-styled info
```

### 2. Enhanced Loading Animations

**Priority**: High
**Effort**: 3-4 hours

Expand animation capabilities beyond basic spinner:
- Multi-style spinners (dots, blocks, arrows, clock, etc.)
- Progress bar with percentage
- Context-specific loading states
- Stacked progress bars for concurrent operations

**File**: `src/utils/loading-animations.rkt`

### 3. Streaming Output Effects

**Priority**: High
**Effort**: 2-3 hours

Enhance streaming LLM output with visual effects:
- Typewriter effect with adjustable speed
- Word-by-word streaming option
- Syntax highlighting for code blocks
- Markdown formatting detection

**File**: `src/utils/stream-effects.rkt`

### 4. Startup Animation

**Priority**: Medium
**Effort**: 4-5 hours

Create a memorable startup sequence:
- Animated multi-frame ASCII art logo
- System check visualization with status indicators
- Animated greeting with contextual tips

**File**: `src/utils/intro-animation.rkt`

### 5. Interactive TUI Elements

**Priority**: Medium
**Effort**: 6-8 hours

Add interactive TUI components:
- Interactive selection menus with arrow keys
- Confirmation dialogs with styled prompts
- Search-as-you-type functionality
- Tab completion visualization

**File**: `src/utils/tui-components.rkt`

### 6. Tool Execution Visualization

**Priority**: High
**Effort**: 2-3 hours

Provide clear visual feedback during tool execution:
- Animated tool call status
- Tool name and parameters display
- Success/error states with visual indicators
- Result preview with syntax highlighting

**File**: `src/utils/tool-visualization.rkt`

### 7. Status Bar

**Priority**: Medium
**Effort**: 4-5 hours

Add a persistent status bar showing key metrics:
- Session ID, model, cost, token count
- Thread and security level display
- Real-time updates during streaming

**File**: `src/utils/status-bar.rkt`

### 8. Enhanced Messages

**Priority**: High
**Effort**: 2-3 hours

Improve all user-facing messages:
- Error messages with styled borders and suggestions
- Success messages with celebration effects
- Warning messages with yellow highlighting
- Info messages with helpful tips

**File**: `src/utils/message-boxes.rkt`

### 9. Session Summary Visualization

**Priority**: Medium
**Effort**: 3-4 hours

Make session summary visually appealing:
- Sparkline charts for token usage
- Bar charts for tool frequency
- Color-coded cost breakdown
- Interactive navigation

**File**: `src/utils/session-summary-viz.rkt`

### 10. Theme Configuration System

**Priority**: Low
**Effort**: 4-5 hours

Allow user customization of visual appearance:
- Theme configuration file support
- Built-in themes (default, cyberpunk, minimal, dracula, solarized)
- Per-terminal theme preferences

**File**: `src/utils/theme-manager.rkt`

---

## GUI Feature Breakdown

### 1. Modern UI Framework Upgrade

**Priority**: Critical
**Effort**: 8-10 hours

**Current State**: Standard Racket GUI widgets look outdated (Windows 95 style)

**Proposed Solution**: Create custom widget wrappers that provide:
- Modern styling with rounded corners, shadows, and gradients
- Hover and click animations
- Smooth transitions and animations
- Consistent spacing and alignment
- Custom color theming support

**File**: `src/gui/widget-framework.rkt`

**Key Components**:
```racket
;; Custom button with modern styling
(new modern-button%
     [parent panel]
     [label "Send"]
     [style '(primary)]  ; primary, secondary, danger, success
     [icon 'send-arrow])  ; SVG/icon support

;; Custom dropdown with search
(new searchable-choice%
     [parent panel]
     [choices models]
     [placeholder "Select model..."]
     [search-enabled #t])

;; Custom text input with validation
(new modern-text-field%
     [parent panel]
     [label "API Key"]
     [type 'password]
     [validation #rx"^[a-zA-Z0-9-]+$"])
```

**Benefits**:
- Modern, consistent appearance across all platforms
- Smooth animations and transitions
- Theme support
- Better accessibility

---

### 2. Enhanced Chat Interface

**Priority**: Critical
**Effort**: 10-12 hours

**Current State**: Plain text editor with simple role headers, no visual distinction between messages

**Proposed Solution**:

**2.1 Message Bubbles**
- User messages: Right-aligned, styled bubbles with gradient background
- Assistant messages: Left-aligned, clean white/gray bubbles
- System messages: Centered, subtle text with icon
- Timestamps on hover or persistent
- Avatar support with initials or icons

**2.2 Syntax Highlighting**
- Inline code highlighting (monospace font, background)
- Code blocks with proper language detection
- Colorized syntax for common languages (Racket, Python, JavaScript, etc.)
- Copy button on code blocks
- Line numbers for multi-line code

**2.3 Markdown Rendering**
- Headers with visual hierarchy
- Bullet points with styled bullets
- Bold/italic text with proper font weight
- Links with underline and hover color
- Block quotes with left border and background

**2.4 Streaming Visualization**
- Character-by-character streaming like modern AI chat interfaces
- Cursor indicator during generation
- Smooth scroll to follow new content
- Typing indicator (..."Typing" bubble) before response

**File**: `src/gui/chat-widget.rkt`

**Visual Mockup**:
```
┌─────────────────────────────────────────────────────────┐
│ 🔍 Model: gpt-5.2 ▼    Mode: code ▼   [🎨] │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────┐              │
│  │ 👤 User                    2:30 PM │              │
│  │ How do I implement a spinner in │              │
│  │ Racket?                      │              │
│  └─────────────────────────────────────────┘              │
│                                                         │
│  ┌─────────────────────────────────────────┐              │
│  │ 🤖 Assistant               2:30 PM │              │
│  │ Here's how to create an animated │              │
│  │ spinner in Racket:             │              │
│  │                                 │              │
│  │ ```racket                         │              │
│  │ (define (spin!) ...)```          │              │
│  │                    [📋 Copy] │              │
│  └─────────────────────────────────────────┘              │
│                                                         │
│  ┌─────────────────────────────────────────┐              │
│  │ 💡 System                    2:31 PM │              │
│  │ Tip: Use Ctrl+Enter for multiline   │              │
│  └─────────────────────────────────────────┘              │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ [📎] Type your message...                    │
│                                                      │
│              [📤 Send]                         │
└─────────────────────────────────────────────────────────┘
```

---

### 3. Icon System

**Priority**: High
**Effort**: 4-6 hours

**Current State**: Pure text labels throughout GUI

**Proposed Solution**: Implement SVG/icon system for visual cues

**Icon Categories**:
- **Navigation**: Home, Settings, Help, Back
- **Actions**: Send, Attach, Clear, Copy, Delete
- **Status**: Success, Error, Warning, Info, Loading
- **Session**: New, Switch, List
- **Tools**: Wrench, Terminal, File, Cloud

**Implementation**:
- Use embedded SVG strings for portability
- Support multiple sizes (16px, 24px, 32px)
- Theme-aware colors (icons adapt to theme)
- Fallback to Unicode characters for accessibility

**File**: `src/gui/icon-library.rkt`

**Usage**:
```racket
(new modern-button%
     [parent panel]
     [label "Send"]
     [icon (get-icon 'send-arrow)])

(new message%
     [parent panel]
     [label "Status: Ready"]
     [icon (get-icon 'check-circle)
      :color 'green])
```

---

### 4. Theme System

**Priority**: High
**Effort**: 6-8 hours

**Current State**: Hardcoded colors (main-gui.rkt:39-45)

**Proposed Solution**: Comprehensive theme system

**4.1 Built-in Themes**
- **Dark Mode** (default): Dark backgrounds, light text
- **Light Mode**: Light backgrounds, dark text
- **Cyberpunk**: Neon colors, dark background
- **Dracula**: Purple/green color scheme
- **Solarized**: Warm, soft colors
- **Minimal**: Black and white only

**4.2 Theme Structure**
```racket
(struct theme
  (name
   primary-color
   secondary-color
   background-color
   foreground-color
   accent-color
   success-color
   warning-color
   error-color
   border-color
   shadow-color
   gradient-start
   gradient-end
   font-family
   font-size))

(define dark-theme
  (theme "Dark"
         (make-object color% 100 149 237)    ; primary
         (make-object color% 60 60 70)       ; secondary
         (make-object color% 30 30 35)       ; bg
         (make-object color% 220 220 220)     ; fg
         (make-object color% 255 200 100)     ; accent
         (make-object color% 76 175 80)      ; success
         (make-object color% 255 193 7)      ; warning
         (make-object color% 220 53 69)      ; error
         (make-object color% 50 50 60)       ; border
         (make-object color% 0 0 0 0.3)     ; shadow
         (make-object color% 45 55 70)       ; gradient-start
         (make-object color% 35 45 60)       ; gradient-end
         "SF Pro Display"                    ; font-family
         14))                               ; font-size
```

**4.3 Theme Management**
- Per-user theme selection saved in config
- Hot-swappable themes (no restart required)
- Theme preview in settings
- Custom theme creation (JSON config)
- Auto theme based on OS preference

**File**: `src/gui/theme-system.rkt`

---

### 5. Loading States and Animations

**Priority**: High
**Effort**: 4-6 hours

**Current State**: No animations, static "Thinking..." status text

**Proposed Solution**: Comprehensive animation system

**5.1 Loading Indicators**
- Spinner animations during API calls
- Skeleton screens for content loading
- Pulse effect on active elements
- Progress bars for file uploads/downloads

**5.2 Transitions**
- Fade in/out for dialogs
- Slide animations for panels
- Button hover/click animations
- Smooth scrolling for chat

**5.3 Message Flow**
- Thinking indicator ("...") before response
- Streaming character-by-character
- Cursor blink during generation
- Smooth scroll to follow content

**File**: `src/gui/animation-engine.rkt`

**Implementation**:
```racket
;; Thinking indicator with bouncing dots
(new thinking-indicator%
     [parent chat-panel]
     [label "AI is thinking"])

;; Progress bar with animated gradient
(new progress-bar%
     [parent panel]
     [value 45]
     [animated #t]
     [style '(gradient)])

;; Skeleton loader for content area
(new skeleton-loader%
     [parent panel]
     [lines 3]
     [style '(shimmer)])
```

---

### 6. Enhanced Toolbar

**Priority**: High
**Effort**: 4-5 hours

**Current State**: Basic dropdowns and checkboxes in horizontal panel

**Proposed Solution**: Modern toolbar with better UX

**6.1 Layout Improvements**
- Collapsible sections for advanced options
- Icon-only mode for space saving
- Responsive design (rearranges on small windows)
- Search/filter for model selection

**6.2 Visual Enhancements**
- Custom dropdowns with icons
- Toggle switches instead of checkboxes
- Tooltips on hover for buttons
- Badges for notifications

**6.3 Quick Actions**
- One-click model switch with history
- Quick preset configurations (fast, cheap, accurate)
- Session switcher dropdown
- Theme toggle button

**File**: `src/gui/toolbar-widget.rkt`

---

### 7. Notifications and Toasts

**Priority**: Medium
**Effort**: 4-5 hours

**Current State**: No notifications, all feedback in status bar

**Proposed Solution**: Non-intrusive notification system

**7.1 Toast Messages**
- Slide-in from bottom or top-right
- Auto-dismiss after configurable timeout
- Success/error/warning variants with icons
- Stacked multiple notifications
- Dismiss button on each

**7.2 In-App Alerts**
- Session save confirmation
- Budget warnings (approaching limits)
- API connection errors
- Security level changes

**7.3 Desktop Notifications**
- System tray integration (optional)
- Notification when response completes
- Tool execution alerts

**File**: `src/gui/notification-system.rkt`

---

### 8. Session Management UI

**Priority**: High
**Effort**: 6-8 hours

**Current State**: Basic list box dialog with session names

**Proposed Solution**: Rich session management interface

**8.1 Session List**
- Card-based layout with thumbnails/previews
- Color-coded by mode (ask, architect, code, semantic)
- Last accessed timestamps with relative time ("2 hours ago")
- Search and filter functionality
- Tags and categories

**8.2 Session Details**
- Token usage visualization
- Cost breakdown
- Message count
- Model usage history
- Export session as JSON/Markdown

**8.3 Session Actions**
- Duplicate session
- Merge sessions
- Archive old sessions
- Bulk operations (delete, export)

**File**: `src/gui/session-manager.rkt`

**Visual Mockup**:
```
┌─────────────────────────────────────────────────────────┐
│ 🔍 Search sessions...                       [New]   │
├─────────────────────────────────────────────────────────┤
│ 🗂️ Recent Sessions                                │
│                                                         │
│  ┌─────────────────────────────────────────┐              │
│  │ 💻 Code: Bug Fix Session          │              │
│  │ Tokens: 12,345  Cost: $0.45         │              │
│  │ Last: 2 hours ago  [⚙️][🗑️] │              │
│  └─────────────────────────────────────────┘              │
│                                                         │
│  ┌─────────────────────────────────────────┐              │
│  │ 📝 Architect: Documentation        │              │
│  │ Tokens: 8,901   Cost: $0.32          │              │
│  │ Last: 1 day ago    [⚙️][🗑️] │              │
│  └─────────────────────────────────────────┘              │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                    [Load More Sessions]                  │
└─────────────────────────────────────────────────────────┘
```

---

### 9. Workflow Management UI

**Priority**: Medium
**Effort**: 4-5 hours

**Current State**: Basic list box dialog

**Proposed Solution**: Visual workflow editor and manager

**9.1 Workflow List**
- Card layout with icons
- Description snippets
- Last used timestamp
- Quick action buttons (Run, Edit, Delete)

**9.2 Workflow Editor**
- Visual step builder
- Drag-and-drop interface
- Parameter configuration
- Preview mode

**File**: `src/gui/workflow-editor.rkt`

---

### 10. Configuration UI

**Priority**: Medium
**Effort**: 4-6 hours

**Current State**: Plain text fields in simple dialog

**Proposed Solution**: Rich configuration interface

**10.1 Tabbed Interface**
- General settings
- Model configuration
- Security settings
- Appearance (theme)
- Advanced options

**10.2 Enhanced Controls**
- Toggle switches for booleans
- Sliders for numeric values
- Color pickers for custom themes
- Model selection with preview

**10.3 Real-time Preview**
- Live theme preview
- Model response time estimation
- Budget visualization

**File**: `src/gui/settings-dialog.rkt`

---

### 11. Tool Execution Visualization

**Priority**: High
**Effort**: 3-4 hours

**Current State**: No visual feedback during tool calls

**Proposed Solution**: Real-time tool execution display

**11.1 Tool Call Panel**
- Expanding panel showing active tools
- Animated progress indicators
- Tool parameters display
- Success/error states

**11.2 Tool Result Formatting**
- Syntax-highlighted output
- Expandable/collapsible results
- Copy to clipboard button
- Export result option

**File**: `src/gui/tool-execution-widget.rkt`

---

### 12. Accessibility Features

**Priority**: High
**Effort**: 4-6 hours

**Current State**: Limited accessibility options

**Proposed Solution**: Comprehensive accessibility

**12.1 Visual Accessibility**
- High contrast mode
- Large text option
- Color blind friendly themes
- Reduced motion option

**12.2 Keyboard Navigation**
- Full keyboard accessibility
- Keyboard shortcuts display
- Focus indicators
- Tab order optimization

**12.3 Screen Reader Support**
- ARIA labels and roles
- Semantic HTML (if web-based)
- Screen reader announcements

**File**: `src/gui/accessibility-manager.rkt`

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

**CLI Tasks**:
- Create `terminal-style.rkt` with color/formatting functions
- Add safe terminal detection
- Create message box system for errors/warnings/success
- Integrate styling into existing CLI output
- Add config option to disable animations

**GUI Tasks**:
- Create `widget-framework.rkt` with modern widget wrappers
- Implement `icon-library.rkt` with SVG icons
- Create `theme-system.rkt` with built-in themes
- Update existing dialogs to use new widgets

**Deliverables**:
- Functional CLI styling library
- Functional GUI widget framework
- Icon library
- Theme system with multiple themes
- Styled CLI messages
- Updated GUI dialogs

---

### Phase 2: Animations (Week 2-3)

**CLI Tasks**:
- Enhance spinner with multiple styles
- Create progress bar component
- Add tool execution visualization
- Integrate animations into tool calls
- Add context loading animations

**GUI Tasks**:
- Implement `animation-engine.rkt`
- Create loading states (spinners, skeletons)
- Add transitions (fade, slide)
- Implement streaming visualization in chat
- Add thinking indicators

**Deliverables**:
- Enhanced CLI loading animations
- CLI tool call visual feedback
- GUI animation system
- Loading states in GUI
- Streaming chat responses in GUI

---

### Phase 3: Streaming & Messaging (Week 3-4)

**CLI Tasks**:
- Implement typewriter effect
- Add syntax highlighting for code
- Detect and format markdown
- Add word-by-word streaming option
- Configurable streaming speed
- LLM integration

**GUI Tasks**:
- Build `chat-widget.rkt` with message bubbles
- Implement syntax highlighting in chat
- Add markdown rendering
- Create streaming character-by-character display
- Add code block formatting with copy buttons

**Deliverables**:
- CLI streaming effects
- CLI syntax highlighting
- GUI chat interface with bubbles
- GUI streaming responses
- Syntax highlighting in both interfaces

---

### Phase 4: Interactive Elements (Week 4-6)

**CLI Tasks**:
- Research TUI libraries or build custom
- Create interactive selection menu
- Add confirmation dialogs
- Implement search-as-you-type
- Integrate into session/thread management

**GUI Tasks**:
- Create `toolbar-widget.rkt` with modern design
- Implement collapsible sections
- Add search/filter for model selection
- Create quick action buttons
- Enhance session switcher

**Deliverables**:
- CLI TUI menus
- CLI confirmation dialogs
- GUI modern toolbar
- GUI search functionality
- Enhanced session management

---

### Phase 5: Polish & Features (Week 6-7)

**CLI Tasks**:
- Create startup animation
- Build status bar
- Enhance session summary
- Add theme configuration system
- Document all new features

**GUI Tasks**:
- Create `notification-system.rkt`
- Implement toast messages
- Build enhanced session manager
- Create workflow editor
- Implement rich settings dialog
- Add accessibility features

**Deliverables**:
- CLI startup animation
- CLI status bar
- GUI notification system
- GUI session manager
- GUI settings with live preview
- Accessibility improvements

---

### Phase 6: Testing & Launch (Week 8)

**CLI Tasks**:
- Test on various terminals (bash, zsh, PowerShell, etc.)
- Performance profiling
- Memory leak checking
- Accessibility testing
- User feedback integration

**GUI Tasks**:
- Test on Windows, macOS, Linux
- Performance optimization
- Cross-platform compatibility
- Theme testing
- Accessibility audit

**Deliverables**:
- Test reports
- Performance benchmarks
- Bug fixes
- Documentation complete
- Release notes

---

## Technical Specifications

### CLI Terminal Compatibility

**Minimum Requirements**:
- ANSI color support (VT100 or higher)
- Unicode/UTF-8 support
- Terminal width ≥ 80 columns
- Terminal height ≥ 24 rows

**Supported Terminals**:
- Linux: gnome-terminal, konsole, xfce4-terminal, alacritty, kitty
- macOS: Terminal.app, iTerm2, Alacritty, Kitty
- Windows: Windows Terminal, PowerShell, Git Bash, WSL
- Remote: SSH sessions, tmux, screen

### GUI Platform Compatibility

**Supported Platforms**:
- Windows 10+ with latest Racket
- macOS 11+ (Big Sur and later)
- Linux (Ubuntu 20.04+, Fedora 35+, Debian 11+, Arch)

**Display Requirements**:
- Minimum resolution: 1024x768
- Recommended resolution: 1280x720 or higher
- Supports HiDPI/Retina displays

**Graphics Requirements**:
- Hardware acceleration preferred (for animations)
- Fallback to software rendering if needed

### Performance Targets

**CLI Performance**:
- Animation frame rate: 10-15 FPS
- Typewriter speed: 10-20ms per character
- Terminal updates: Batched to reduce flicker
- Memory overhead: <5MB additional
- CPU impact: <2% during idle, <5% during animations

**GUI Performance**:
- 60 FPS animations (smooth)
- Streaming rendering: <50ms latency
- Window resize: <100ms to redraw
- Memory overhead: <50MB additional
- CPU impact: <5% during idle, <10% during streaming

### ANSI Escape Code Reference

See CLI Feature Breakdown section for full ANSI code reference.

---

## Code Architecture

### CLI Module Structure

```
src/utils/
├── terminal-style.rkt       ; Color and formatting system
├── loading-animations.rkt    ; Spinners and progress bars
├── stream-effects.rkt       ; Streaming output effects
├── intro-animation.rkt      ; Startup animation
├── tui-components.rkt       ; Interactive UI components
├── tool-visualization.rkt   ; Tool execution feedback
├── status-bar.rkt           ; Status bar component
├── message-boxes.rkt        ; Styled message boxes
├── session-summary-viz.rkt   ; Enhanced session summary
└── theme-manager.rkt        ; Theme configuration
```

### GUI Module Structure

```
src/gui/
├── main-gui.rkt           ; Main entry point (update existing)
├── widget-framework.rkt     ; Modern widget wrappers
├── chat-widget.rkt        ; Enhanced chat interface
├── icon-library.rkt        ; SVG icon system
├── theme-system.rkt        ; Theme management
├── animation-engine.rkt     ; Animation system
├── toolbar-widget.rkt      ; Enhanced toolbar
├── notification-system.rkt  ; Toast notifications
├── session-manager.rkt      ; Session management UI
├── workflow-editor.rkt      ; Workflow editor
├── settings-dialog.rkt      ; Configuration UI
└── accessibility-manager.rkt ; Accessibility features
```

### Shared Components

```
src/shared/
├── theme-config.rkt       ; Shared theme definitions
├── constants.rkt          ; Shared colors, sizes, fonts
└── utils.rkt             ; Shared utility functions
```

---

## Testing Strategy

### CLI Testing

For each new module:
- Color/formatting functions output correct codes
- Animation frames render correctly
- Progress bar accurate at various percentages
- Message boxes format correctly
- Theme loading and application

### GUI Testing

For each new component:
- Widgets render correctly on all platforms
- Animations smooth and performant
- Theme switching works without bugs
- Keyboard navigation accessible
- Screen reader compatibility (if applicable)

### Integration Tests

- Styled output displays correctly in various terminals
- Animations don't interfere with core functionality
- Tool execution visualization syncs with actual tool calls
- Status bar updates reflect real-time changes
- GUI streaming effects work with actual LLM responses

### Cross-Platform Tests

- Test on Windows (10, 11)
- Test on macOS (11, 12, 13, 14)
- Test on Linux (Ubuntu, Fedora, Debian, Arch)
- Test with HiDPI displays
- Test with various terminal emulators

### Performance Tests

- Memory usage during long animations
- CPU impact during streaming
- Terminal refresh rate limits
- GUI frame rate consistency
- Concurrent operation performance

### Accessibility Tests

- Readable without colors (high contrast mode)
- Screen reader compatibility
- Keyboard navigation only
- Motion sensitivity (disable animations)
- Text resizing support

---

## Milestones and Timeline

### Week 1-2: Foundation
**Milestone**: Basic styling systems operational

**CLI Deliverables**:
- ✅ terminal-style.rkt created
- ✅ Message boxes implemented
- ✅ Terminal detection working
- ✅ Error messages styled
- ✅ Config option to disable

**GUI Deliverables**:
- ✅ Widget framework created
- ✅ Icon library implemented
- ✅ Theme system with multiple themes
- ✅ Dialogs updated with new widgets

**Demo**: Styled CLI messages and modern GUI dialogs

---

### Week 2-3: Animations
**Milestone**: Visual feedback for all operations

**CLI Deliverables**:
- ✅ Enhanced spinners
- ✅ Progress bars
- ✅ Tool call visualization
- ✅ Context loading animation
- ✅ Integration complete

**GUI Deliverables**:
- ✅ Animation engine created
- ✅ Loading states implemented
- ✅ Transitions added
- ✅ Streaming visualization in chat
- ✅ Thinking indicators

**Demo**: Animated tool execution (CLI) and streaming chat (GUI)

---

### Week 3-4: Streaming & Messaging
**Milestone**: Delightful LLM output

**CLI Deliverables**:
- ✅ Typewriter effect
- ✅ Syntax highlighting
- ✅ Markdown rendering
- ✅ Configurable speed
- ✅ LLM integration

**GUI Deliverables**:
- ✅ Chat widget with bubbles
- ✅ Syntax highlighting in chat
- ✅ Markdown rendering
- ✅ Streaming character-by-character
- ✅ Code block formatting

**Demo**: Streaming responses with syntax highlighting (both interfaces)

---

### Week 4-6: Interactive Elements
**Milestone**: TUI and enhanced GUI controls

**CLI Deliverables**:
- ✅ Interactive menus
- ✅ Confirmation dialogs
- ✅ Search-as-you-type
- ✅ Session/thread selection
- ✅ Input prompts

**GUI Deliverables**:
- ✅ Modern toolbar
- ✅ Collapsible sections
- ✅ Search functionality
- ✅ Quick action buttons
- ✅ Enhanced session switcher

**Demo**: Interactive session selector (CLI) and modern toolbar (GUI)

---

### Week 6-7: Polish & Features
**Milestone**: Complete visual experience

**CLI Deliverables**:
- ✅ Startup animation
- ✅ Status bar
- ✅ Enhanced summary
- ✅ Theme system
- ✅ Documentation

**GUI Deliverables**:
- ✅ Notification system
- ✅ Toast messages
- ✅ Session manager
- ✅ Settings dialog
- ✅ Accessibility features

**Demo**: Full animated startup with status bar (CLI) and notifications (GUI)

---

### Week 8: Launch
**Milestone**: Production-ready

**Tasks**:
- ✅ All tests passing
- ✅ Performance optimized
- ✅ Documentation complete
- ✅ User guide updated
- ✅ Release notes written

**Demo**: Full walkthrough of all CLI and GUI features

---

## Resources and Dependencies

### Racket Libraries to Consider

**Existing in project**:
- `racket/gui` - GUI framework (already have)
- `racket/port` - For output handling
- `racket/string` - String manipulation
- `racket/system` - Terminal control
- `racket/thread` - Animation threads

**External libraries**:
- `termbox` - TUI library (if needed for CLI)
- `json` - Theme configuration (already have)
- `db-lib` - Already in project

### GUI Framework Considerations

**Option 1: Continue with Racket GUI**
- Pros: Native integration, no dependencies
- Cons: Requires significant custom widget work

**Option 2: Use Web-based GUI (Electron-like)**
- Pros: Modern UI, easy styling, rich ecosystem
- Cons: Heavy dependencies, cross-platform complexity

**Option 3: Mixed Approach (Recommended)**
- Use Racket GUI for backend/logic
- Create custom styled widgets on top
- Maintain native performance

**Recommendation**: Option 3 - Build custom widget framework on Racket GUI

### Development Tools

- Terminal emulator testing suite
- Screen recording tools (vhs - already used in project)
- Performance profiling tools
- Accessibility testing tools

### Time Allocation

- **CLI Development**: 80 hours (6 weeks × ~13 hours)
- **GUI Development**: 100 hours (6 weeks × ~17 hours)
- **Testing**: 24 hours (3 hours/week)
- **Documentation**: 16 hours
- **Total**: ~220 hours (vs. 160 hours for CLI-only)

---

## Success Metrics

### Quantitative Metrics

**CLI Metrics**:
- Performance: No more than 5% CPU overhead from animations
- Terminal Compatibility: Works on 90%+ of tested terminals
- User Satisfaction: 4+ star rating from beta testers
- Code Quality: 90%+ test coverage for new CLI modules

**GUI Metrics**:
- Frame Rate: 60 FPS for animations (target), minimum 30 FPS
- Platform Compatibility: Works on 95%+ of tested platforms
- User Satisfaction: 4+ star rating from beta testers
- Code Quality: 85%+ test coverage for new GUI modules
- Theme Support: 5+ built-in themes working

### Qualitative Metrics

- **Visual Appeal**: Users describe interfaces as "beautiful" or "delightful"
- **Usability**: New users can navigate features without reading docs
- **Memorability**: Users remember startup experience
- **Professionalism**: Sets high bar for open-source tools
- **Enjoyment**: Users enjoy using it daily
- **Consistency**: CLI and GUI feel like one cohesive product

### Technical Metrics

**CLI**:
- Maintainability: Clear module separation
- Extensibility: Easy to add new themes/animations
- Reliability: No crashes from visual components
- Accessibility: Works without colors/animations

**GUI**:
- Responsiveness: Smooth animations, no lag
- Consistency: Same theme across all components
- Reliability: No crashes from visual components
- Accessibility: Full keyboard navigation support

---

## Risk Mitigation

### Potential Issues

1. **Terminal Incompatibility** (CLI)
   - Mitigation: Graceful degradation to plain text
   - Detection: Terminal capability detection
   - Fallback: Disable animations automatically

2. **Performance Impact**
   - Mitigation: Performance profiling early
   - Monitoring: CPU/memory during animations
   - Optimization: Batch updates, reduce redraws

3. **Cross-Platform GUI Issues**
   - Mitigation: Test early on all platforms
   - Detection: Platform-specific code paths
   - Fallback: Simplified rendering for old systems

4. **User Preference**
   - Mitigation: Configuration options
   - Default: Balanced animations
   - Override: Environment variables and config

5. **Complexity Increase**
   - Mitigation: Clear module separation
   - Documentation: Comprehensive comments
   - Testing: High test coverage

---

## Future Enhancements

### Beyond Initial Scope

**CLI Enhancements**:
1. **Sound Effects** - Success sounds, error sounds (optional)
2. **3D ASCII Art** - Special occasions, holiday themes
3. **Particle Effects** - Confetti, rain (optional)
4. **Screensaver Mode** - Animated idle screen, stats visualization

**GUI Enhancements**:
1. **Split View** - Compare sessions side-by-side
2. **Voice Input** - Speech-to-text for messages
3. **Export Formats** - PDF, HTML, Markdown export
4. **Plugin System** - Community extensions
5. **Cloud Sync** - Sync sessions across devices
6. **Collaboration** - Multi-user chat sessions
7. **AI Art Generation** - Image generation integration in chat
8. **Video Responses** - Support for multimodal AI

### Collaboration Between CLI and GUI

- **Shared Configuration**: Both interfaces read same config
- **Shared Sessions**: CLI and GUI access same session data
- **Shared Themes**: Theme system applies to both
- **Synchronized State**: Changes reflect in both interfaces

---

## Conclusion

This plan provides a comprehensive roadmap for transforming **both** Chrysalis Forge CLI and GUI into visually stunning and delightful experiences. The phased approach allows for iterative development, testing, and feedback while ensuring each phase delivers real value to users.

By combining visual appeal with functional excellence, Chrysalis Forge will stand out in both CLI and GUI tool landscapes and become a memorable tool that users genuinely enjoy using.

### Key Takeaways

- **Foundation First**: Build styling systems before adding animations
- **User-Centric**: All enhancements improve UX, not just flash
- **Performance**: Never sacrifice functionality for visuals
- **Accessible**: Work on all terminals/platforms, respect preferences
- **Iterative**: Test and refine at each phase
- **Consistent**: CLI and GUI share themes and visual identity
- **Modern**: GUI uses contemporary design patterns
- **Delightful**: Both interfaces feel polished and enjoyable

### Next Steps

1. Review and approve this plan
2. Set up development environments for CLI and GUI testing
3. Begin Phase 1: Foundation (CLI and GUI in parallel)
4. Schedule weekly progress reviews
5. Engage beta testers early for both interfaces

---

## Appendix

### A. ANSI Color Reference

Full table of ANSI escape codes included in Technical Specifications section.

### B. Terminal Compatibility Matrix

| Terminal | Colors | Unicode | Animations | Status |
|----------|--------|---------|------------|--------|
| gnome-terminal | ✅ | ✅ | ✅ | Full Support |
| iTerm2 | ✅ | ✅ | ✅ | Full Support |
| Windows Terminal | ✅ | ✅ | ✅ | Full Support |
| Terminal.app | ✅ | ✅ | ✅ | Full Support |
| PowerShell | ⚠️ | ✅ | ⚠️ | Partial |
| Git Bash | ✅ | ✅ | ✅ | Full Support |
| VSCode Terminal | ✅ | ✅ | ✅ | Full Support |

### C. GUI Platform Compatibility Matrix

| Platform | GUI Framework | HiDPI | Animations | Status |
|----------|----------------|---------|------------|--------|
| Windows 10+ | Racket GUI | ✅ | ✅ | Full Support |
| macOS 11+ | Racket GUI | ✅ | ✅ | Full Support |
| Ubuntu 20.04+ | Racket GUI | ✅ | ✅ | Full Support |
| Fedora 35+ | Racket GUI | ✅ | ✅ | Full Support |
| Debian 11+ | Racket GUI | ✅ | ✅ | Full Support |
| Arch Linux | Racket GUI | ✅ | ✅ | Full Support |

### D. Example Config Files

See theme configuration in CLI and GUI Feature Breakdown sections.

### E. User Feedback Template

```markdown
## Visual Enhancement Feedback

**Interface**: [CLI / GUI / Both]
**Terminal/GUI**: [e.g., iTerm2 on macOS]
**OS**: [e.g., macOS 14]
**Theme**: [e.g., cyberpunk]

**Likes**:
- ...

**Dislikes**:
- ...

**Suggestions**:
- ...

**Issues**:
- ...
```

---

**Document Version**: 2.0 (Added GUI enhancements)
**Last Updated**: January 18, 2026
**Author**: Chrysalis Forge Team
**Status**: Draft - Pending Review
