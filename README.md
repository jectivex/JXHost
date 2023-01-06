# JXHost

```mermaid
flowchart TB
    HostApp -.-> PetStoreModule
    HostApp --> JXHost
    PetStoreModule --> JXBridge
    JXHost --> JXSwiftUI
    JXHost --> JXPod
    JXPod --> JXKit
    JXPod -.-> FilePod
    JXPod -.-> NetPod
    JXPod -.-> LocationPod
    HostApp -.-> AnimalFarmModule
    AnimalFarmModule --> JXBridge
    JXSwiftUI --> JXBridge
    JXBridge --> JXKit
    JXKit --> JavaScriptCore

```
