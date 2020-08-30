//
//  FaceOverlay.swift
//  ARTestProject
//
//  Created by Yuri on 30.08.2020.
//

import Foundation
import ARKit

class FaceOverlay: NSObject, ARSCNViewDelegate {

    var contentNode: SCNNode?
    var occlusionNode: SCNNode!
    var faceOverlayContent: SCNReferenceNode!

    override init() {
        guard let filePath = Bundle.main.path(forResource: "glasses", ofType: "scn", inDirectory: "Models.scnassets")  else { return }
        let referenceURL = URL(fileURLWithPath: filePath)
        faceOverlayContent = SCNReferenceNode(url: referenceURL)
        faceOverlayContent!.load()
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let sceneView = renderer as? ARSCNView,
            anchor is ARFaceAnchor else { return nil }

        #if targetEnvironment(simulator)
            #error("ARKit is not supported in iOS Simulator")
        #else

        contentNode = SCNNode()
        let faceGeometry = ARSCNFaceGeometry(device: sceneView.device!)!
        faceGeometry.firstMaterial!.colorBufferWriteMask = []
        occlusionNode = SCNNode(geometry: faceGeometry)
        occlusionNode.renderingOrder = -1
        contentNode!.addChildNode(occlusionNode)

        contentNode!.addChildNode(faceOverlayContent!)
        #endif

        return contentNode
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceGeometry = occlusionNode.geometry as? ARSCNFaceGeometry,
            let faceAnchor = anchor as? ARFaceAnchor
            else { return }

        faceGeometry.update(from: faceAnchor.geometry)
    }
}
