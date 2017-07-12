
import Cocoa
import AVFoundation

/*
    Provides convenient helper methods to work with AVAudioEngine
*/
class AudioEngineHelper {
    
    private let audioEngine: AVAudioEngine
    private var nodes: [AVAudioNode]
    
    init(engine: AVAudioEngine) {
        self.audioEngine = engine
        nodes = [AVAudioNode]()
    }
    
    // Attach a single node to the engine
    func addNode(node: AVAudioNode) {
        nodes.append(node)
        audioEngine.attachNode(node)
    }
    
    // Attach multiple nodes to the engine
    func addNodes(nodes: [AVAudioNode]) {
        self.nodes.appendContentsOf(nodes)
        for node in nodes {
            audioEngine.attachNode(node)
        }
    }
    
    // Connects all nodes in sequence
    func connectNodes() {
        
        var input: AVAudioNode, output: AVAudioNode
        
        // At least 2 nodes required for this to work
        if (nodes.count >= 2) {
            for i in 0...nodes.count - 2 {
                
                input = nodes[i]
                output = nodes[i + 1]
                
                audioEngine.connect(input, to: output, format: nil)
            }
        }
        
        audioEngine.connect(nodes[nodes.count - 1], to: audioEngine.mainMixerNode, format: nil)
    }
    
    // Reconnects two nodes with the given audio format (required when a track change occurs)
    func reconnectNodes(inputNode: AVAudioNode, outputNode: AVAudioNode, format: AVAudioFormat) {
        
        audioEngine.disconnectNodeOutput(inputNode)
        audioEngine.connect(inputNode, to: outputNode, format: format)
    }
    
    func prepareAndStart() {
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch let error as NSError {
            print(error.description)
        }
    }
}