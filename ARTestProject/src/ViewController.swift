//
//  ViewController.swift
//  ARTestProject
//
//  Created by Yuri on 30.08.2020.
//

import UIKit
import ARKit
import SceneKit

class ViewController: UIViewController, ARSessionDelegate {

    @IBOutlet var sceneView: ARSCNView!

    var currentFaceAnchor: ARFaceAnchor?
    var content: FaceOverlay!
    var recorder = VideoRecorder()


    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true

        setup()

    }
    func setup () {
        self.content = FaceOverlay()
        if let anchor = currentFaceAnchor, let node = sceneView.node(for: anchor),
           let newContent = self.content.renderer(sceneView, nodeFor: anchor) {
            node.addChildNode(newContent)
        }

        recorder.sceneView = sceneView
        recorder.setup { (error) in }
    }
    @IBAction func startStopRecording(_ sender: UIButton) {
        if recorder.isRecording {
            sender.setTitle("Start", for: .normal)
            recorder.stopRecording()
            return
        }
        sender.setTitle("Stop", for: .normal)
        recorder.startRecording()
    }

   
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIApplication.shared.isIdleTimerDisabled = true
        resetTracking()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }

        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")

        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }

    func resetTracking() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Error handling

    func displayErrorMessage(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.resetTracking()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }
    
}

extension ViewController: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        currentFaceAnchor = faceAnchor

        if node.childNodes.isEmpty, let contentNode = content.renderer(renderer, nodeFor: faceAnchor) {
            node.addChildNode(contentNode)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard anchor == currentFaceAnchor,
            let contentNode = content.contentNode,
            contentNode.parent == node
            else { return }

        content.renderer(renderer, didUpdate: contentNode, for: anchor)
        recorder.didUpdateAtTime(time: self.sceneView.session.currentFrame!.timestamp)
    }

}

