import SwiftUI
import AVFoundation

// MARK: - Landscape full-screen preview
struct LandscapePreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _LandscapePreviewUIView {
        let v = _LandscapePreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: _LandscapePreviewUIView, context: Context) {}
}

final class _LandscapePreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - Portrait PiP preview (shows the center 9:16 crop of the same session)
/// The trick: embed the preview layer at full-landscape width inside a clipped
/// portrait container, offset so only the center 9:16 strip is visible.
struct PortraitPiPPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _PortraitPiPUIView {
        let v = _PortraitPiPUIView()
        v.configure(with: session)
        return v
    }

    func updateUIView(_ uiView: _PortraitPiPUIView, context: Context) {}
}

final class _PortraitPiPUIView: UIView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    func configure(with session: AVCaptureSession) {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        layer.masksToBounds = true
        layer.cornerRadius  = 8
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // bounds is the PiP box (9:16 portrait, e.g. 90×160)
        let pip = bounds
        // Full 16:9 preview at the same height
        let fullW = pip.height * 16.0 / 9.0
        let xOffset = -(fullW - pip.width) / 2.0
        previewLayer.frame = CGRect(x: xOffset, y: 0, width: fullW, height: pip.height)
    }
}
