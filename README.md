# NoteFlow

NoteFlow는 SwiftUI와 SwiftData로 만든 iOS 메모 앱입니다. 블록 기반 메모 작성, 폴더/태그 관리, 잠금 메모, iCloud 동기화, Apple Intelligence Foundation Models와 Gemini 기반 AI 보조 기능을 한 앱 안에서 제공합니다.

## 주요 기능

- 블록 기반 메모 작성
  - 텍스트, 제목, 체크리스트, 인용, 구분선, 표, 이미지, 파일 블록 지원
  - 슬래시 명령어와 블록 편집 UI 제공
- 메모 정리
  - 폴더, 태그, 즐겨찾기, 최근 삭제 항목 관리
  - 메모 검색과 정렬 지원
- 잠금 메모
  - Face ID 인증을 통한 잠긴 메모 보호
- Apple Intelligence 기반 메모 보조
  - Foundation Models를 활용한 온디바이스 메모 정리
  - 제목/요약/태그 추천
  - 문장 다듬기, 확장, 맞춤법 교정, 이어쓰기, 사용자 지정 명령
  - 지원되지 않는 기기나 모델 미준비 상태에서는 로컬 fallback 정리 사용
- Gemini 기반 문서/미디어 AI 기능
  - 손글씨 인식
  - 회의 음성 요약
  - 파일 요약
  - 영수증, 문서, 명함 스캔
  - AI 처리 취소, 단계별 진행 문구, 오류 유형별 안내
- iCloud 동기화 및 백업
  - SwiftData + CloudKit private database 기반 메모 동기화
  - iCloud 상태 확인
  - 수동 백업 내보내기/가져오기
  - iCloud Drive 고정 백업 파일 기반 강제 업로드/강제 불러오기

## 기술 스택

- Swift
- SwiftUI
- SwiftData
- CloudKit
- iCloud Drive
- Apple Foundation Models
- Gemini API
- LocalAuthentication

## 프로젝트 구조

```text
NoteFlow/
├── LocalMind/
│   ├── Config/
│   │   ├── Shared.xcconfig
│   │   └── Secrets.xcconfig.example
│   ├── LocalMind/
│   │   ├── Models/
│   │   ├── Services/
│   │   ├── Views/
│   │   ├── Info.plist
│   │   ├── LocalMind.entitlements
│   │   └── LocalMindApp.swift
│   └── LocalMind.xcodeproj
├── .gitignore
└── README.md
```

## 실행 준비

### 1. Gemini API 키 설정

`LocalMind/Config/Secrets.xcconfig.example` 파일을 참고해 `Secrets.xcconfig`를 생성합니다.

```xcconfig
GEMINI_API_KEY = YOUR_GEMINI_API_KEY
```

`Secrets.xcconfig`는 `.gitignore`에 포함되어 있어 저장소에 올라가지 않습니다.

Gemini API 키가 없으면 일반 메모 기능과 Apple Intelligence 기반 온디바이스 메모 보조 기능은 사용할 수 있지만, 손글씨 인식/회의 요약/파일 요약/스캔 같은 Gemini 기능은 설정 필요 안내가 표시됩니다.

### 2. Apple Intelligence / Foundation Models

NoteFlow의 기본 AI 제공자는 Apple Intelligence입니다. 메모 편집 화면의 정리, 제목/요약/태그 추천, 글쓰기 보조 기능은 `FoundationModels` 프레임워크의 온디바이스 모델을 우선 사용합니다.

Apple Intelligence를 사용하려면 지원 기기와 OS, 활성화된 Apple Intelligence 설정이 필요합니다. 기기가 지원되지 않거나 모델이 준비되지 않은 경우 앱은 간단한 로컬 fallback 정리/글쓰기 기능을 사용합니다.

### 3. iCloud / CloudKit 설정

CloudKit 동기화를 사용하려면 Apple Developer 계정과 실제 iCloud 컨테이너 설정이 필요합니다.

현재 프로젝트는 다음 컨테이너를 사용합니다.

```text
iCloud.kotlinsun.LocalMind
```

Xcode의 `Signing & Capabilities`에서 아래 항목이 켜져 있어야 합니다.

- iCloud
  - CloudKit
  - iCloud Documents
  - Container: `iCloud.kotlinsun.LocalMind`
- Background Modes
  - Remote notifications
- Push Notifications

`LocalMind.entitlements`에는 CloudKit, CloudDocuments, Push 알림 환경이 설정되어 있습니다.

## 실행 방법

1. Xcode에서 `LocalMind/LocalMind.xcodeproj`를 엽니다.
2. `LocalMind` scheme을 선택합니다.
3. `LocalMind/Config/Secrets.xcconfig`에 Gemini API 키를 설정합니다.
4. Signing Team과 iCloud capability가 올바른지 확인합니다.
5. 실제 기기 또는 시뮬레이터에서 실행합니다.

CloudKit 동기화와 Push 기반 변경 반영은 실제 기기에서 확인하는 것을 권장합니다. 시뮬레이터에서는 iCloud/CloudKit 백그라운드 동작이 실제 기기와 다르게 보일 수 있습니다.

## iCloud 동기화 기준

NoteFlow의 메모 데이터는 SwiftData 모델을 CloudKit private database와 연결해 동기화합니다.

- 메모, 폴더, 블록, 할 일, 삭제 기록이 동기화 대상입니다.
- 삭제 반영은 `DeletedNoteTombstone` 모델을 함께 사용합니다.
- 앱 내부에는 CloudKit 강제 동기화 API를 직접 호출하지 않습니다.
- iCloud 상태와 네트워크 상태에 따라 반영 시점이 지연될 수 있습니다.
- 강제 업로드/강제 불러오기는 CloudKit DB 직접 제어가 아니라 iCloud Drive 백업 파일 기반 복구 기능입니다.

## 백업 기능

설정 화면의 `iCloud 및 백업`에서 다음 기능을 제공합니다.

- 수동 백업 내보내기
- 수동 백업 가져오기
- 강제 업로드
  - 현재 기기의 데이터를 iCloud Drive 고정 백업 파일로 저장합니다.
- 강제 불러오기
  - iCloud Drive 고정 백업 파일로 현재 기기 데이터를 전체 교체합니다.
  - 실행 전 확인 alert가 표시됩니다.

## 개발 메모

- 테스트 실행은 필수가 아니며, 현재 작업 흐름에서는 코드상 오류 확인 위주로 점검합니다.
- 기본 확인 명령:

```sh
git diff --check
plutil -lint LocalMind/LocalMind/Info.plist LocalMind/LocalMind.xcodeproj/project.pbxproj LocalMind/LocalMind/LocalMind.entitlements
xcodebuild -list -project LocalMind/LocalMind.xcodeproj
```

## 주의사항

- `Secrets.xcconfig`에는 실제 Gemini API 키가 들어가므로 커밋하지 않습니다.
- CloudKit capability 변경 후에는 기존 설치 앱을 삭제하고 다시 설치해야 entitlement 변경이 명확히 반영될 수 있습니다.
- iCloud 동기화 검증은 같은 Apple 계정으로 로그인된 실제 기기 2대에서 확인하는 것이 가장 정확합니다.
