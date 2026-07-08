# NoteFlow

NoteFlow는 SwiftUI와 SwiftData로 만든 iOS 메모 앱입니다. 블록 기반 편집, 폴더/태그 정리, 잠금 메모, iCloud 실시간 동기화, Apple Intelligence Foundation Models와 Gemini 기반 AI 도구를 한 앱 안에서 제공합니다.

## 화면 미리보기

NoteFlow의 핵심 화면입니다. 메모 작성, AI 도구, iCloud 백업 설정 흐름을 중심으로 구성되어 있습니다.

<table>
  <tr>
    <td align="center">
      <img width="260" alt="메모 목록 화면" src="https://github.com/user-attachments/assets/0b60cb29-95b8-40b8-9fc1-19eb514679d4" />
      <br />
      <sub>메모 목록</sub>
    </td>
    <td align="center">
      <img width="260" alt="블록 기반 편집 화면" src="https://github.com/user-attachments/assets/9e65b554-b5e5-46bb-a049-52a00e7e0c2b" />
      <br />
      <sub>블록 기반 편집</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img width="260" alt="AI 도구 화면" src="https://github.com/user-attachments/assets/9632a9fa-bd83-4543-bc0f-09d65227cc21" />
      <br />
      <sub>AI 도구</sub>
    </td>
    <td align="center">
      <img width="260" alt="AI 결과 미리보기 화면" src="https://github.com/user-attachments/assets/e686f62c-c2d2-46b2-95a1-86d787e6783f" />
      <br />
      <sub>AI 결과 미리보기</sub>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="2">
      <img width="260" alt="iCloud 및 백업 설정 화면" src="https://github.com/user-attachments/assets/b825bc40-0c70-4dfe-b53d-329017e713a4" />
      <br />
      <sub>iCloud 및 백업</sub>
    </td>
  </tr>
</table>

## 한눈에 보기

- 블록 단위로 메모를 작성하고 재배치할 수 있는 노트 편집기
- 폴더, 태그, 즐겨찾기, 최근 삭제 항목을 활용한 메모 관리
- Face ID 기반 잠금 메모
- Apple Intelligence Foundation Models 기반 온디바이스 메모 보조
- Gemini API 기반 손글씨 인식, 회의 요약, 파일 요약, 문서/영수증/명함 스캔
- SwiftData + CloudKit private database 기반 iCloud 동기화
- 수동 백업과 iCloud Drive 고정 백업 파일 기반 복구 기능

## 주요 기능

### 메모 작성

- 텍스트, 제목, 체크리스트, 인용, 구분선, 표, 이미지, 파일 블록 지원
- 슬래시 명령어 기반 블록 추가
- 블록별 메뉴, 드래그 앤 드롭, 첨부 파일 관리
- 메모 제목, 본문, 태그, 폴더, 즐겨찾기 관리

### 메모 정리

- 폴더별 메모 분류
- 태그 기반 메모 탐색
- 즐겨찾기와 최근 수정 메모 확인
- 최근 삭제 항목과 복원/영구 삭제 흐름
- 메모 검색과 정렬

### 잠금 메모

- Face ID 인증을 통한 잠긴 메모 보호
- 잠금 상태에서 민감한 메모 내용 노출 방지

### Apple Intelligence 기반 메모 보조

NoteFlow의 메모 편집 화면에서는 Apple Intelligence Foundation Models를 우선 사용합니다. 지원 기기에서는 온디바이스 모델로 메모 내용을 분석하고 글쓰기를 보조합니다.

- 제목 추천
- 요약 생성
- 태그 추천
- 문장 다듬기
- 문장 확장
- 맞춤법 교정
- 이어쓰기
- 사용자 지정 명령

지원되지 않는 기기, Apple Intelligence 비활성화, 모델 미준비 상태에서는 간단한 로컬 fallback 결과를 제공합니다.

### Gemini 기반 AI 도구

`AI 도구` 탭에서는 외부 입력을 메모로 바꾸는 Gemini 기반 기능을 제공합니다.

| 구분 | 기능 | 입력 |
| --- | --- | --- |
| 메모로 바꾸기 | 손글씨 인식 | 이미지 |
| 메모로 바꾸기 | 회의 요약 | 음성 |
| 메모로 바꾸기 | 파일 요약 | 파일 |
| 문서 정리하기 | 문서 스캔 | 이미지 |
| 문서 정리하기 | 영수증 스캔 | 이미지 |
| 문서 정리하기 | 명함 스캔 | 이미지 |

Gemini 기능은 다음 UX를 포함합니다.

- API 키 누락, 네트워크 오류, 응답 오류, 빈 응답/파싱 오류 구분 안내
- 긴 AI 작업 취소
- 실제 처리 단계 기반 진행 문구
- 결과 미리보기 후 메모로 저장

### iCloud 동기화 및 백업

NoteFlow는 SwiftData 모델을 CloudKit private database와 연결해 메모 데이터를 동기화합니다.

- 메모, 폴더, 블록, 할 일, 삭제 기록 동기화
- CloudKit push notification 기반 변경 반영
- iCloud 계정 상태 안내
- 수동 백업 내보내기/가져오기
- iCloud Drive 고정 백업 파일 기반 강제 업로드/강제 불러오기

강제 업로드/강제 불러오기는 CloudKit DB를 직접 제어하는 기능이 아니라, 복구용 iCloud Drive 백업 파일을 쓰고 읽는 기능입니다.

## 기술 스택

- Swift
- SwiftUI
- SwiftData
- CloudKit
- iCloud Drive
- Apple Foundation Models
- Gemini API
- LocalAuthentication
- UniformTypeIdentifiers
- PhotosUI
- AVFoundation

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

`LocalMind/Config/Secrets.xcconfig.example` 파일을 참고해 `LocalMind/Config/Secrets.xcconfig` 파일을 생성합니다.

```xcconfig
GEMINI_API_KEY = YOUR_GEMINI_API_KEY
```

`Secrets.xcconfig`는 `.gitignore`에 포함되어 있어 저장소에 올라가지 않습니다.

Gemini API 키가 없어도 일반 메모 기능과 Apple Intelligence 기반 온디바이스 메모 보조 기능은 사용할 수 있습니다. 다만 손글씨 인식, 회의 요약, 파일 요약, 문서/영수증/명함 스캔 같은 Gemini 기능은 설정 필요 안내가 표시됩니다.

### 2. Apple Intelligence / Foundation Models

Apple Intelligence 기반 기능을 사용하려면 지원 기기, 지원 OS, 활성화된 Apple Intelligence 설정이 필요합니다.

지원 조건을 만족하지 않는 경우 앱은 가능한 범위에서 로컬 fallback 정리/글쓰기 결과를 제공합니다.

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

## 데이터 동기화 기준

NoteFlow의 메모 데이터는 SwiftData 모델을 CloudKit private database와 연결해 동기화합니다.

- 동기화 대상: 폴더, 메모, 블록, 할 일, 삭제 기록
- 삭제 반영: `DeletedNoteTombstone` 모델을 함께 사용
- 반영 방식: CloudKit import/export와 push notification에 의존
- 앱 내 처리: 앱 활성화 시 CloudKit 상태 확인과 로컬 화면 갱신
- 제한 사항: CloudKit의 서버 fetch를 앱에서 강제로 즉시 실행하지 않음

iCloud 상태와 네트워크 상태에 따라 다른 기기의 변경 사항이 반영되는 시점은 지연될 수 있습니다.

## 백업 기능

설정 화면의 `iCloud 및 백업`에서 다음 기능을 제공합니다.

| 기능 | 설명 |
| --- | --- |
| 수동 백업 내보내기 | 원하는 위치에 `.noteflowbackup` 파일을 저장합니다. |
| 수동 백업 가져오기 | 백업 파일을 선택해 병합하거나 전체 교체합니다. |
| 강제 업로드 | 현재 기기 데이터를 iCloud Drive 고정 백업 파일로 저장합니다. |
| 강제 불러오기 | iCloud Drive 고정 백업 파일로 현재 기기 데이터를 전체 교체합니다. |

백업 파일은 CloudKit 실시간 동기화와 별개인 복구용 파일입니다. 잠긴 메모 내용과 첨부 파일도 포함될 수 있으므로 저장 위치와 공유 범위에 주의해야 합니다.

## 보안 및 비밀 값 관리

- 실제 Gemini API 키는 `LocalMind/Config/Secrets.xcconfig`에만 저장합니다.
- `Secrets.xcconfig`는 `.gitignore`에 포함되어 커밋되지 않습니다.
- `Info.plist`에는 빌드 시 `$(GEMINI_API_KEY)` 값이 주입됩니다.
- 앱 코드는 `Bundle.main`의 `GeminiAPIKey` 값을 읽어 Gemini 요청에 사용합니다.
- 공개 저장소에는 `Secrets.xcconfig.example`만 포함합니다.

## 개발 확인 명령

테스트 실행은 필수가 아니며, 현재 작업 흐름에서는 코드상 오류 확인 위주로 점검합니다.

```sh
git diff --check
plutil -lint LocalMind/LocalMind/Info.plist LocalMind/LocalMind.xcodeproj/project.pbxproj LocalMind/LocalMind/LocalMind.entitlements
xcodebuild -list -project LocalMind/LocalMind.xcodeproj
```

## 문제 해결

### Gemini API 키가 없다고 표시되는 경우

- `LocalMind/Config/Secrets.xcconfig` 파일이 있는지 확인합니다.
- 파일 안에 `GEMINI_API_KEY = ...` 값이 있는지 확인합니다.
- Xcode에서 다시 빌드합니다.

### iCloud 동기화가 바로 보이지 않는 경우

- 같은 Apple 계정으로 로그인된 실제 기기에서 확인합니다.
- iCloud Drive와 NoteFlow의 iCloud 권한이 켜져 있는지 확인합니다.
- 네트워크 상태를 확인합니다.
- CloudKit 반영은 즉시 fetch가 보장되지 않아 약간의 지연이 있을 수 있습니다.

### CloudKit entitlement 변경 후 이상하게 동작하는 경우

- 기존 설치 앱을 삭제하고 다시 설치합니다.
- Xcode의 Signing Team과 iCloud container 설정을 다시 확인합니다.
- `LocalMind.entitlements`와 `Info.plist`의 iCloud 관련 설정을 확인합니다.

## 주의사항

- `Secrets.xcconfig`에는 실제 Gemini API 키가 들어가므로 커밋하지 않습니다.
- iCloud 동기화 검증은 같은 Apple 계정으로 로그인된 실제 기기 2대에서 확인하는 것이 가장 정확합니다.
- 강제 불러오기는 현재 기기 데이터를 전체 교체하는 작업이므로 실행 전 백업 파일 내용을 반드시 확인해야 합니다.
