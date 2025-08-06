# Gemmatry 🧮✨

**AI-Powered Math Problem Solver with On-Device Gemma 3n 4B Model**

Gemmatry is a Flutter-based mobile application that leverages Google's Gemma 3n 4B language model to solve mathematical problems directly on your device. With advanced OCR capabilities, multi-turn conversations, and professional mathematical rendering, Gemmatry provides a comprehensive solution for students, educators, and math enthusiasts.

## 🌟 Key Features

### 🤖 **On-Device AI Processing**
- **Gemma 3n 4B Model Integration**: Powered by Google's state-of-the-art Gemma 3n 4B model
- **GPU Acceleration**: Utilizes TensorFlow Lite delegates for optimal performance
- **Privacy-First**: All processing happens locally - no data leaves your device
- **Offline Capable**: Works completely offline once the model is installed

### 📸 **Advanced Image Processing**
- **OCR Text Extraction**: Extract mathematical problems from photos
- **Image Preprocessing**: Advanced algorithms for better text recognition
- **Mathematical Symbol Recognition**: Specialized patterns for math notation
- **Multi-Input Support**: Handle text-only, image-only, or combined inputs

### 💬 **Intelligent Problem Solving**
- **Two-Phase Processing**: Extraction followed by comprehensive solving
- **Step-by-Step Solutions**: Detailed explanations with mathematical reasoning
- **Multi-Turn Conversations**: Ask follow-up questions about solutions
- **Context Preservation**: Maintains conversation history and problem context

### 🎨 **Professional UI/UX**
- **Natural Notebook Design**: Warm, artisan paper-inspired interface
- **LaTeX Math Rendering**: Beautiful mathematical notation display
- **Markdown Support**: Rich text formatting for solutions
- **Responsive Layout**: Optimized for various screen sizes

### ⚡ **Background Processing**
- **Background Solving**: Continue processing when app is backgrounded
- **Smart Notifications**: Get notified when solutions are ready
- **Progress Tracking**: Real-time updates on solving progress
- **Resource Management**: Efficient memory and battery usage

### 📚 **Problem Management**
- **History Tracking**: Save and revisit solved problems
- **Search Functionality**: Find problems by content or date
- **Title Generation**: AI-powered descriptive titles for problems
- **Database Storage**: Local SQLite database for fast access

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK**: Version 3.32.0 or higher
- **Android Studio** or **VS Code** with Flutter extensions
- **Android Device/Emulator**: Android 7.0 (API level 24) or higher
- **Gemma Model File**: 4.2GB model file (see installation instructions)

### Installation

1. **Clone the Repository**
   ```bash
   git clone https://github.com/Honoriel/Gemmatry.git
   cd Gemmatry
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Model Installation**
   - Download the Gemma 3n 4B model file (4.2GB)
   - Place it in: `/storage/emulated/0/Android/data/com.gerfalcon.example.gemmatry/files/`
   - The app will automatically detect and validate the model

4. **Build and Run**
   ```bash
   flutter run
   ```

### Model Setup

The app requires the Gemma 3n 4B model file to function. The model manager will:
- Search common download locations
- Validate model file integrity
- Copy to app-accessible directory
- Initialize with TensorFlow Lite acceleration

## 🏗️ Architecture

### Core Components

- **MathSolverService**: Central service managing AI inference and problem solving
- **OCRService**: Advanced image processing and text extraction
- **DatabaseService**: Local data persistence with SQLite
- **NotificationService**: Background task notifications
- **ModelManager**: Gemma model lifecycle management

### Data Flow

1. **Input Processing**: OCR extraction or direct text input
2. **Problem Analysis**: AI-powered question extraction and refinement
3. **Solution Generation**: Structured problem solving with step-by-step explanations
4. **Response Parsing**: Extract answers and explanations from AI output
5. **UI Rendering**: Display with LaTeX math and markdown formatting

### AI Processing Pipeline

- **Extraction Phase**: Identify and structure mathematical problems
- **Solving Phase**: Generate comprehensive solutions with reasoning
- **Context Management**: Maintain conversation state for follow-ups
- **Memory Optimization**: Efficient chat instance management

## 🛠️ Technical Stack

### Framework & Languages
- **Flutter**: Cross-platform mobile development
- **Dart**: Primary programming language
- **SQLite**: Local database storage

### AI & ML
- **Google Gemma 3n 4B**: On-device language model
- **TensorFlow Lite**: Model inference engine
- **flutter_gemma**: Flutter integration package
- **Google ML Kit**: OCR and text recognition

### UI & Rendering
- **flutter_math_fork**: LaTeX mathematical notation
- **flutter_markdown**: Rich text formatting
- **Google Fonts**: Typography system

### Background Processing
- **WorkManager**: Background task scheduling
- **flutter_local_notifications**: User notifications
- **Isolates**: Concurrent processing

## 📱 Usage

### Solving Problems

1. **Take a Photo**: Capture mathematical problems from textbooks, worksheets, or whiteboards
2. **Or Type Directly**: Enter problems using text input
3. **Get Solutions**: Receive detailed step-by-step explanations
4. **Ask Follow-ups**: Continue the conversation with additional questions

### Background Solving

1. **Enable Background Mode**: Toggle the background solving option
2. **Start Solving**: Initiate problem solving
3. **Background the App**: Switch to other apps while processing continues
4. **Get Notified**: Receive notifications when solutions are ready

### Managing History

- **View Past Problems**: Browse your solving history
- **Search Solutions**: Find specific problems or topics
- **Generate Titles**: Let AI create descriptive titles
- **Delete Problems**: Remove unwanted entries

## 🔧 Configuration

### Model Settings
- **Max Tokens**: 4096 (configurable)
- **GPU Acceleration**: Automatically enabled when available
- **Image Support**: Enabled for visual problem analysis

### UI Customization
- **Theme**: Natural notebook design with warm earth tones
- **Math Rendering**: LaTeX with proper baseline alignment
- **Font System**: Google Fonts integration

## 🤝 Contributing

We welcome contributions to Gemmatry! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Guidelines

- Follow Flutter/Dart best practices
- Maintain comprehensive error handling
- Add documentation for new features
- Test on multiple devices and screen sizes


