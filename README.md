# Turbodoc iOS

A native iOS bookmark management application built with SwiftUI and SwiftData. Turbodoc allows users to save, organize, and search through various types of content including links, images, videos, text, and files across all their Apple devices.

## 🚀 Quick Start

### Prerequisites

- Xcode 15.0+
- iOS 18.5+ deployment target
- macOS 14.0+ for development
- Apple Developer Account (for device testing)
- Supabase project (for backend services)

### Installation

1. Clone the repository
2. Open `Turbodoc.xcodeproj` in Xcode
3. Configure Supabase settings in `Configuration/SupabaseConfig.swift`
4. Build and run (⌘+R)

### Configuration

Update your Supabase configuration:

1. Open `Configuration/SupabaseConfig.swift`
2. Add your Supabase URL and anonymous key
3. Ensure your API endpoints match the backend configuration

## 📱 Features

### Current Implementation (Phase 1)

- ✅ **Authentication System**: Complete sign-in, sign-up, and password reset
- ✅ **Tab Navigation**: Home, Search, and Profile tabs
- ✅ **Bookmark Management**: Create, read, update, delete bookmarks
- ✅ **SwiftData Integration**: Local data persistence with cloud sync
- ✅ **API Integration**: Full integration with Turbodoc API backend
- ✅ **Modern UI**: SwiftUI with custom components and styling

### Planned Features

- **Share Extension**: Save content from other apps
- **Content Processing**: Support for various file types and media
- **Advanced Search**: Full-text search with filtering
- **Tag Management**: Organize bookmarks with custom tags
- **Offline Support**: Work seamlessly without internet connection

## 🏗️ Architecture

### Tech Stack

- **Framework**: SwiftUI for declarative UI
- **Data**: SwiftData for local persistence
- **Networking**: URLSession with structured API service
- **Authentication**: Supabase Auth integration
- **Architecture**: MVVM pattern with Coordinator pattern for navigation

### Project Structure

```txt
Turbodoc/
├── TurbodocApp.swift              # App entry point and configuration
├── RootView.swift                 # Root navigation coordinator
├── Authentication/                # Authentication system
│   ├── AuthenticationCoordinator.swift
│   ├── Services/
│   │   └── AuthenticationService.swift
│   └── Views/
│       ├── SignInView.swift
│       ├── SignUpView.swift
│       └── ForgotPasswordView.swift
├── Main/                         # Core app navigation
│   ├── MainTabView.swift         # Tab bar controller
│   ├── Tabs/                     # Tab view controllers
│   │   ├── HomeView.swift        # Bookmark listing and management
│   │   ├── SearchView.swift      # Search functionality
│   │   └── ProfileView.swift     # User profile and settings
│   └── Views/
│       └── AddBookmarkView.swift # Bookmark creation
├── Data/                         # Data layer
│   ├── Models/
│   │   ├── User.swift           # User data model
│   │   ├── BookmarkItem.swift   # Bookmark data model
│   │   └── APIModels.swift      # API response models
│   └── Services/
│       ├── APIService.swift     # API communication
│       └── NetworkService.swift # Network utilities
├── Common/                      # Shared utilities
│   ├── Extensions/              # Swift extensions
│   │   ├── String+Extensions.swift
│   │   └── View+Extensions.swift
│   └── UI/                      # UI components
│       ├── ButtonStyles.swift
│       ├── CardView.swift
│       ├── Constants.swift
│       ├── InputStyles.swift
│       └── LoadingButton.swift
├── Configuration/               # App configuration
│   ├── APIConfig.swift         # API endpoints
│   ├── SupabaseConfig.swift    # Supabase configuration
│   ├── Debug.xcconfig          # Debug build settings
│   └── Release.xcconfig        # Release build settings
└── Assets.xcassets/            # App assets and icons
```

### Key Components

#### Data Models

**BookmarkItem**: Core data model supporting multiple content types

```swift
@Model
class BookmarkItem {
    var id: UUID
    var title: String
    var url: String?
    var contentType: ContentType // link, image, video, text, file
    var timeAdded: Date
    var tags: [String]
    var status: ItemStatus // unread, read, archived
    var userId: String
    // ... additional metadata fields
}
```

**User**: User authentication and profile data

```swift
@Model 
class User {
    var id: String
    var email: String
    // Profile information and preferences
}
```

#### Services

**AuthenticationService**: Handles all authentication operations

- Sign in/sign up with email and password
- Password reset functionality
- Session management and token handling
- Integration with Supabase Auth

**APIService**: Manages all API communications

- RESTful endpoint interactions
- Authentication token management
- Error handling and retry logic
- Response parsing and validation

#### UI Components

**Custom Button Styles**: Consistent button appearance
**CardView**: Reusable card container for content
**LoadingButton**: Button with loading state support
**Input Styles**: Standardized form input styling

### Authentication Flow

1. **App Launch**: Check for existing session
2. **Authentication**: Present sign-in flow if needed
3. **Session Management**: Maintain authentication state
4. **Token Refresh**: Automatic token renewal
5. **Logout**: Clean session termination

### Data Synchronization

- **Local First**: All data stored locally with SwiftData
- **Cloud Sync**: Automatic synchronization with backend API
- **Conflict Resolution**: Last-write-wins strategy
- **Offline Support**: Full functionality without network

## 🔧 Development

### Build Commands

| Action | Shortcut | Description |
|--------|----------|-------------|
| Build | ⌘+B | Compile the project |
| Run | ⌘+R | Build and run on simulator/device |
| Test | ⌘+U | Run unit and UI tests |
| Clean | ⌘+Shift+K | Clean build folder |
| Archive | ⌘+Shift+Return | Create distribution archive |

### Dependencies

Dependencies are managed through Swift Package Manager:

- **Supabase Swift SDK** (v2.30.1): Backend integration and authentication
- All dependencies resolved in `Package.resolved`

### Configuration Files

- `Debug.xcconfig`: Development environment settings
- `Release.xcconfig`: Production environment settings
- `SupabaseConfig.swift`: Supabase URL and key configuration
- `APIConfig.swift`: API endpoint definitions

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI declarative patterns
- Implement proper error handling
- Maintain clean separation of concerns
- Write comprehensive documentation

## 📦 Deployment

### Development Build

1. Select your development team in project settings
2. Choose target device or simulator
3. Build and run (⌘+R)

### TestFlight Distribution

1. Archive the app (⌘+Shift+Return)
2. Upload to App Store Connect
3. Configure TestFlight testing
4. Distribute to internal/external testers

### App Store Release

1. Prepare app metadata and screenshots
2. Configure App Store Connect listing
3. Submit for App Store Review
4. Release to App Store upon approval

### Bundle Configuration

- **Bundle ID**: `ai.turbodoc.ios.Turbodoc`
- **Development Team**: Configured in project settings
- **Code Signing**: Automatic signing enabled
- **Minimum iOS Version**: 18.5

## 🔄 Integration

### Backend API

The app integrates seamlessly with the Turbodoc API:

- RESTful endpoints for all operations
- JWT authentication with automatic refresh
- Consistent error handling and status codes
- Support for batch operations and pagination

### Cross-Platform Sync

- Shared data models with web and API
- Consistent bookmark schema across platforms
- Real-time synchronization capabilities
- Conflict resolution strategies

## 🧪 Testing

### Unit Tests

Test coverage for:

- Data models and business logic
- API service layer
- Authentication workflows
- Utility functions and extensions

### UI Tests

Automated testing for:

- Authentication flows
- Bookmark management operations
- Navigation between tabs
- Search functionality

### Manual Testing

- Test on various iOS devices and screen sizes
- Verify offline functionality
- Test authentication edge cases
- Validate data synchronization

## 🔍 Architecture Patterns

### MVVM Pattern

- **Models**: SwiftData entities and API response models
- **Views**: SwiftUI views with declarative syntax
- **ViewModels**: ObservableObject classes managing view state

### Coordinator Pattern

- **AuthenticationCoordinator**: Manages authentication flow
- **Navigation**: Centralized navigation logic
- **Deep Linking**: Support for URL schemes and universal links

### Repository Pattern

- **APIService**: Abstracts backend communication
- **Local Storage**: SwiftData for offline capabilities
- **Synchronization**: Automated sync between local and remote data

## 🚀 Performance

### Optimization Strategies

- **Lazy Loading**: Load content on demand
- **Image Caching**: Efficient image storage and retrieval
- **Data Pagination**: Load bookmarks in batches
- **Background Processing**: Handle sync operations off main thread

### Memory Management

- Proper use of weak references in closures
- Efficient SwiftData query patterns
- Image memory management for large collections
- Background task completion handling

## 📚 Resources

### Development

- [Swift Documentation](https://docs.swift.org/swift-book/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [SwiftData Guide](https://developer.apple.com/documentation/swiftdata)
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/ios)

### Backend Integration

- [Turbodoc API Documentation](../turbodoc-api/README.md)
- [Supabase Swift SDK](https://github.com/supabase/supabase-swift)
- [RESTful API Design](https://restfulapi.net/)

### Apple Ecosystem

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
