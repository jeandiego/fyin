import SwiftUI

// Fy 120 × 120 pt, traçado sobre a referência aprovada (Fyin.pen, "DS · 03 Mascote").
// Três formas chapadas (folha, corpo lime, rosto branco) e dois olhos; sem brilho nem sombra.
// Os olhos viram os três pontos de "Pensando" (componentes Fy / *).
struct Fy: View {
    var blink = false
    var thinking = false

    private let dots: [(x: CGFloat, d: CGFloat, opacity: Double)] = [(628, 22, 0.35), (670, 26, 0.65), (714, 30, 1)]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / FyShape.box.width
            ZStack(alignment: .topLeading) {
                FyShape(ops: FyShape.leaf).fill(Color.qAccent)
                FyShape(ops: FyShape.body).fill(Color.qAccent)
                FyShape(ops: FyShape.face).fill(.white)
                FyShape(ops: FyShape.eyeL).fill(Color.qInk)
                    .scaleEffect(y: blink ? 0.2 : 1, anchor: FyShape.unit(632, 577))
                    .opacity(thinking ? 0 : 1)
                FyShape(ops: FyShape.eyeR).fill(Color.qInk)
                    .scaleEffect(y: blink ? 0.2 : 1, anchor: FyShape.unit(714, 566.5))
                    .opacity(thinking ? 0 : 1)
                ForEach(dots.indices, id: \.self) { i in
                    Circle().fill(Color.qInk.opacity(dots[i].opacity))
                        .frame(width: dots[i].d * s, height: dots[i].d * s)
                        .position(x: (dots[i].x - FyShape.box.minX) * s, y: (566 - FyShape.box.minY) * s)
                        .opacity(thinking ? 1 : 0)
                }
            }
        }
        .frame(width: 120, height: 120)
    }
}

// Caminhos SVG absolutos (M, C, Z) no espaço da referência de 1080 px; `box` é o viewBox do mascote no .pen.
private struct FyShape: Shape {
    static let box = CGRect(x: 268, y: 253, width: 545, height: 545)
    static let leaf = parse("M377 268C377.2 263.3 377.8 259.3 380 257C382.2 254.7 382.5 254.5 390 254C397.5 253.5 414.2 253.5 425 254C435.8 254.5 443.3 254.5 455 257C466.7 259.5 483.3 263.5 495 269C506.7 274.5 516.7 282.2 525 290C533.3 297.8 540.2 307.7 545 316C549.8 324.3 551.8 331.8 554 340C556.2 348.2 557.5 358.3 558 365C558.5 371.7 562.5 377.3 557 380C551.5 382.7 537 381.3 525 381C513 380.7 498.3 380.5 485 378C471.7 375.5 458.3 372.8 445 366C431.7 359.2 414.5 346.3 405 337C395.5 327.7 392.3 318.7 388 310C383.7 301.3 380.8 292 379 285C377.2 278 376.8 272.7 377 268Z")
    static let body = parse("M455 396C471.7 395 490 396.5 505 397C520 397.5 532.5 396.8 545 399C557.5 401.2 568.3 398.2 580 410C591.7 421.8 606.7 438.3 615 470C623.3 501.7 628.3 558.3 630 600C631.7 641.7 627.5 689 625 720C622.5 751 619.2 773.3 615 786C610.8 798.7 610 794.2 600 796C590 797.8 570.8 796.8 555 797C539.2 797.2 521.7 797 505 797C488.3 797 471.7 797.7 455 797C438.3 796.3 420 795.5 405 793C390 790.5 375.8 785.8 365 782C354.2 778.2 348.2 775.3 340 770C331.8 764.7 323.7 758.3 316 750C308.3 741.7 299.7 730 294 720C288.3 710 285.5 701.7 282 690C278.5 678.3 275 663.3 273 650C271 636.7 270.2 621.7 270 610C269.8 598.3 271.2 588.8 272 580C272.8 571.2 272.8 567.3 275 557C277.2 546.7 280 531.3 285 518C290 504.7 298.3 488.2 305 477C311.7 465.8 318.3 458.5 325 451C331.7 443.5 338.3 437.3 345 432C351.7 426.7 358.3 422.8 365 419C371.7 415.2 378.3 411.7 385 409C391.7 406.3 393.3 405.2 405 403C416.7 400.8 438.3 397 455 396Z")
    static let face = parse("M471 410C480.8 407.2 491 404.8 505 403C519 401.2 541.7 401.2 555 399C568.3 396.8 576.7 393.8 585 390C593.3 386.2 598.3 380.5 605 376C611.7 371.5 618.3 366.5 625 363C631.7 359.5 638.3 356.7 645 355C651.7 353.3 658.3 352.8 665 353C671.7 353.2 678.3 354 685 356C691.7 358 698.3 360.7 705 365C711.7 369.3 718.3 374.8 725 382C731.7 389.2 738.3 396.5 745 408C751.7 419.5 758.3 434.2 765 451C771.7 467.8 779.2 490.8 785 509C790.8 527.2 796 544.8 800 560C804 575.2 807.2 587.5 809 600C810.8 612.5 811.2 623.3 811 635C810.8 646.7 810.2 659.2 808 670C805.8 680.8 802.5 690 798 700C793.5 710 787 721.7 781 730C775 738.3 770 743.3 762 750C754 756.7 742.5 764.7 733 770C723.5 775.3 715.3 778.7 705 782C694.7 785.3 683.5 788.3 671 790C658.5 791.7 643.5 792.2 630 792C616.5 791.8 602.5 791.5 590 789C577.5 786.5 566.7 781.8 555 777C543.3 772.2 530.8 766.2 520 760C509.2 753.8 500.5 748.3 490 740C479.5 731.7 466.5 720 457 710C447.5 700 440.8 691.7 433 680C425.2 668.3 415.8 651.7 410 640C404.2 628.3 401.5 620 398 610C394.5 600 391.5 591.7 389 580C386.5 568.3 383.5 553.3 383 540C382.5 526.7 384.5 510 386 500C387.5 490 389.3 486.7 392 480C394.7 473.3 397.5 466.7 402 460C406.5 453.3 411.7 446.7 419 440C426.3 433.3 437.3 425 446 420C454.7 415 461.2 412.8 471 410Z")
    static let eyeL = parse("M621.4 527.3C636.4 524.1 653.3 543.8 659.1 571.2C664.9 598.7 657.5 623.5 642.6 626.7C627.6 629.9 610.7 610.2 604.9 582.8C599.1 555.3 606.5 530.5 621.4 527.3Z")
    static let eyeR = parse("M703.4 516.4C717.1 513.5 733.1 533.5 738.9 561.2C744.8 588.9 738.4 613.7 724.6 616.6C710.9 619.5 694.9 599.5 689.1 571.8C683.2 544.1 689.6 519.3 703.4 516.4Z")

    let ops: [(Character, [CGFloat])]

    static func unit(_ x: CGFloat, _ y: CGFloat) -> UnitPoint {
        UnitPoint(x: (x - box.minX) / box.width, y: (y - box.minY) / box.height)
    }

    static func parse(_ d: String) -> [(Character, [CGFloat])] {
        var out: [(Character, [CGFloat])] = []
        var num = ""
        func push() {
            if let v = Double(num) { out[out.count - 1].1.append(CGFloat(v)) }
            num = ""
        }
        for ch in d {
            if ch.isLetter { push(); out.append((ch, [])) } else if ch == " " { push() } else { num.append(ch) }
        }
        push()
        return out
    }

    func path(in rect: CGRect) -> Path {
        let s = rect.width / Self.box.width
        func pt(_ v: [CGFloat], _ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + (v[i] - Self.box.minX) * s, y: rect.minY + (v[i + 1] - Self.box.minY) * s)
        }
        var path = Path()
        for (cmd, v) in ops {
            switch cmd {
            case "M": path.move(to: pt(v, 0))
            case "C": stride(from: 0, to: v.count, by: 6).forEach { path.addCurve(to: pt(v, $0 + 4), control1: pt(v, $0), control2: pt(v, $0 + 2)) }
            default: path.closeSubpath()
            }
        }
        return path
    }
}
