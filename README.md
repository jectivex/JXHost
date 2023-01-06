# JXHost


```mermaid
flowchart TB
    HostApp -.-> HeadlessModule
    HostApp((Host App)) -.-> PetStoreModule
    HostApp -.-> DatePlannerModule
            
    subgraph JXHost
      subgraph Modules[Dynamic Modules]
        HeadlessModule(Headless Module)
        PetStoreModule(Pet Store)
        DatePlannerModule(Date Planner)
      end
      
      subgraph Pods[Native Pods]
        subgraph StandardPods[Standard Pods]
          SwiftUIPod[(JXSwiftUI)]
          FilePod[(FilePod)]
          NetPod[(NetPod)]
        end
        CustomPod[(CustomPod)]
      end
    end
    
    HeadlessModule --> JXBridge

    PetStoreModule -.-> SwiftUIPod
    
    DatePlannerModule -.-> SwiftUIPod
    DatePlannerModule -.-> FilePod
    DatePlannerModule -.-> NetPod
    DatePlannerModule -.-> CustomPod

    FilePod --> JXBridge
    NetPod --> JXBridge
    SwiftUIPod --> JXBridge
    CustomPod --> JXBridge

    JXBridge --> JXKit
    
    JXKit --> JavaScriptCore[JavaScriptCore]

classDef HostApp fill:white,stroke:#333,stroke-width:4px
class HostApp HostApp

classDef PetStoreModule fill:lightgray,stroke:#333,stroke-width:0.5px
classDef HeadlessModule fill:lightgreen,stroke:#333,stroke-width:0.5px
classDef DatePlannerModule fill:lightsalmon,stroke:#333,stroke-width:0.5px

class PetStoreModule PetStoreModule
class HeadlessModule HeadlessModule
class DatePlannerModule DatePlannerModule

classDef CustomPod fill:lightsalmon,stroke:#333,stroke-width:0.5px
class CustomPod CustomPod

classDef Modules fill:aliceblue,stroke:#333,stroke-width:0.5px
class Modules Modules

classDef Pods fill:wheat,stroke:#333,stroke-width:0.5px
class Pods Pods

classDef JavaScriptCore fill:orange,stroke:#333,stroke-width:0.5px
class JavaScriptCore JavaScriptCore

class di orange

```
