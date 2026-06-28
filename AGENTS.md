# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Turbodoc is an iOS bookmark management application built with SwiftUI and SwiftData. The app allows users to save, organize, and search through various types of content including links, images, videos, text, and files. It's being developed in 3 phases as outlined in the PRD documents.

## Development Commands

### Build and Run

- **Build**: Use Xcode to build the project (⌘+B)
- **Run**: Use Xcode to run on simulator or device (⌘+R)
- **Clean**: Product → Clean Build Folder (⌘+Shift+K)

### Dependencies

- Dependencies are managed through Swift Package Manager
- Main dependency: Supabase Swift SDK (v2.30.1) for backend integration
- Package resolved dependencies are tracked in `Package.resolved`

### Testing

- **Unit Tests**: Not yet implemented - will be added in development phases
- **UI Tests**: Not yet implemented - will be added in development phases

## Architecture

### Current State (Initial Template)

The project currently contains a basic SwiftUI template with:

- `TurbodocApp.swift`: Main app entry point with SwiftData model container
- `ContentView.swift`: Basic list view for demonstrating SwiftData
- `Item.swift`: Simple SwiftData model with timestamp

### Target Architecture (From PRDs)

The application will be restructured according to the 3-phase development plan:

#### Phase 1: Authentication & Core Infrastructure

- Supabase authentication system
- Basic tab bar navigation (Home, Search, Profile)
- Swift Data models for User and BookmarkItem
- Mock API service layer

#### Phase 2: Share Extension & Content Handling

- iOS Share Extension target
- Content processing for different file types
- File storage system with App Groups
- Real API integration with Supabase

#### Phase 3: Content Display & Search

- Full bookmark display and management
- Comprehensive search functionality
- Tag management system
- CSV import for existing bookmarks

### Key Dependencies

- **SwiftUI**: Modern declarative UI framework
- **SwiftData**: Data persistence layer
- **Supabase Swift**: Backend authentication and database
- **App Groups**: Data sharing between main app and share extension

### File Structure (Planned)

```txt
Turbodoc/
├── App/
│   ├── TurbodocApp.swift
│   └── SceneDelegate.swift
├── Authentication/
│   ├── Services/AuthenticationService.swift
│   └── Views/[Auth ViewControllers]
├── Main/
│   ├── TabBarController.swift
│   └── Tabs/[Home, Search, Profile]
├── Data/
│   ├── Models/[User, BookmarkItem]
│   └── Services/[APIService, DataManager]
├── Common/
│   ├── Extensions/
│   └── UI/
└── Resources/
```

## Development Notes

### Bundle Identifier

- Main app: `ai.turbodoc.ios.Turbodoc`
- Share extension (Phase 2): `ai.turbodoc.ios.Turbodoc.shareextension`

### Minimum iOS Version

- iOS 18.5+ (as configured in project settings)
- Uses SwiftData which requires iOS 17+

### Team Configuration

- Development Team: 7NA9PJ7WYB
- Automatic code signing enabled

## Phase Development Strategy

Follow the PRD documents in the `prds/` folder for detailed implementation guidance:

- `phase1.md`: Core infrastructure and authentication
- `phase2.md`: Share extension and content handling  
- `phase3.md`: Content display, search, and tag management

Each phase builds upon the previous one, with clear deliverables and testing requirements outlined in the respective PRD files.

## Important Implementation Details

### Supabase Configuration

- Will need environment-specific configuration for Supabase URL and anon key
- Authentication will use email/password flow initially
- Database schema includes tables for users, bookmarks, and tags

### Share Extension (Phase 2)

- Will support URLs, images, videos, text, and files
- Uses App Groups for data sharing: `group.com.yourcompany.turbodoc`
- Implements background processing for content saving

### Content Management (Phase 3)

- Local file storage with organized directory structure
- Thumbnail generation for visual content
- Full-text search across all bookmark content
- Tag-based organization system
