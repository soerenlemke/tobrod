package dom

import "core:strings"
import "core:testing"

@(test)
test_mask :: proc(t: ^testing.T) {
	// a data URL keeps its case and loses its escapes; size, position and
	// repeat like Wikipedia's icons; -webkit- and the shorthand; a gradient
	// counts as no mask; var() keeps the case of the address too
	doc, err := parse(`<style>
		.a { -webkit-mask-image: url("data:image/svg+xml;utf8,<svg width=\"20\"><path d=\"M1 1H9\"/></svg>");
		     mask-size: 20px; mask-position: center; mask-repeat: no-repeat }
		.b { mask: url(Icons/X.svg) right bottom / contain repeat-x, url(other.svg) }
		.c { mask-image: linear-gradient(#000, transparent) }
		.d { --icon: url(Icons/Y.svg); mask-image: var(--icon); mask-size: cover }
		</style><h1 class="a"></h1><h2 class="b"></h2><h3 class="c"></h3><h4 class="d"></h4>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	a := find_element(doc.root, "h1").style.mask
	testing.expect_value(t, a.image, `data:image/svg+xml;utf8,<svg width="20"><path d="M1 1H9"/></svg>`)
	testing.expect_value(t, a.size, Layer_Size.Explicit)
	testing.expect_value(t, a.width, px(20))
	testing.expect_value(t, a.height.unit, Length_Unit.Auto)
	testing.expect_value(t, a.position, [2]Length{{unit = .Percent, value = 50}, {unit = .Percent, value = 50}})
	testing.expect_value(t, a.no_repeat, [2]bool{true, true})

	b := find_element(doc.root, "h2").style.mask
	testing.expect_value(t, b.image, "Icons/X.svg")
	testing.expect_value(t, b.size, Layer_Size.Contain)
	testing.expect_value(t, b.position, [2]Length{{unit = .Percent, value = 100}, {unit = .Percent, value = 100}})
	testing.expect_value(t, b.no_repeat, [2]bool{false, true})

	testing.expect_value(t, find_element(doc.root, "h3").style.mask.image, "")
	d := find_element(doc.root, "h4").style.mask
	testing.expect_value(t, d.image, "Icons/Y.svg")
	testing.expect_value(t, d.size, Layer_Size.Cover)
}

@(test)
test_background_image :: proc(t: ^testing.T) {
	// the shorthand with a color, the longhands (first layer), an edge offset
	doc, err := parse(`<style>
		.a { background: #fff url("Img/A.png") no-repeat center / 20px }
		.b { background-image: url(Img/B.png), linear-gradient(red, blue); background-position: right 4px top; background-size: cover; background-repeat: repeat-x }
		.c { background: linear-gradient(red, blue) }
		</style><h1 class="a"></h1><h2 class="b"></h2><h3 class="c"></h3>`)
	if e, ok := err.?; ok {
		testing.fail_now(t, e.message)
	}
	defer destroy(doc)

	a := find_element(doc.root, "h1").style
	testing.expect_value(t, a.background, Color{255, 255, 255, 255})
	testing.expect_value(t, a.background_image.image, "Img/A.png")
	testing.expect_value(t, a.background_image.no_repeat, [2]bool{true, true})
	testing.expect_value(t, a.background_image.width, px(20))

	b := find_element(doc.root, "h2").style.background_image
	testing.expect_value(t, b.image, "Img/B.png")
	testing.expect_value(t, b.size, Layer_Size.Cover)
	testing.expect_value(t, b.no_repeat, [2]bool{false, true})
	testing.expect_value(t, b.position.y, Length{unit = .Percent, value = 0})
	testing.expect_value(t, b.position.x.unit, Length_Unit.Calc)
	testing.expect_value(t, b.position.x.calc[.Percent], 100)
	testing.expect_value(t, b.position.x.calc[.Px], -4)

	testing.expect_value(t, find_element(doc.root, "h3").style.background_image.image, "")
}

@(test)
test_absolute_urls :: proc(t: ^testing.T) {
	// relative url()s in a stylesheet are made absolute against it; others stay
	resolve :: proc(base, ref: string) -> (string, bool) {
		return strings.concatenate({base, "|", ref}, context.temp_allocator), true
	}
	css := `a{background:url(img/a.png)} b{background:url( "b.png" )} c{mask:url(data:image/svg+xml,x)} d{background:url(https://x/y.png)} e{background:url(/root.png)}`
	got := absolute_urls(css, "S", resolve)
	testing.expect_value(t, got, `a{background:url("S|img/a.png")} b{background:url("S|b.png" )} c{mask:url(data:image/svg+xml,x)} d{background:url(https://x/y.png)} e{background:url("S|/root.png")}`)
}
