/// Switch the bottom bar's individual animation techniques on and off here.
/// Each effect is independent – set a flag to false to remove it.
const kBottomBarMotion = BottomBarMotion(
  velocityBounce: true, // bounce graded by scroll speed
  arcs: true, // the bubble travels along an arc
  directionalSquash: true, // stretch along the direction of travel
  iconSpring: true, // the icon has its own, looser spring
  iconHop: true, // the icon makes a small hop on the way
  labelSlide: true, // labels slide in towards the centre
  navItemLag: true, // navigation icons lag behind, staggered
  // Off: the scroll belongs to the list, not the bottom bar, so the bar
  // should stay still once it has reached its shape. Use it for elements
  // you drag directly (sheets, cards).
  rubberBand: false,
  impact: true, // the navigation bar gets an impact on landing
  pressFeedback: true, // squeezes on touch
  stretchyPill: true, // the tab bar's pill stretches
  gooey: true, // the shapes flow together when close
  colorBlend: true, // colours blend while the shapes are connected
  blobImpact: true, // blob reaction when the shapes catch and release
  contentBlend: true, // content shows through the other shape and dissolves
);

class BottomBarMotion {
  const BottomBarMotion({
    this.velocityBounce = true,
    this.arcs = true,
    this.directionalSquash = true,
    this.iconSpring = true,
    this.iconHop = true,
    this.labelSlide = true,
    this.navItemLag = true,
    this.rubberBand = false,
    this.impact = true,
    this.pressFeedback = true,
    this.stretchyPill = true,
    this.gooey = true,
    this.colorBlend = true,
    this.blobImpact = true,
    this.contentBlend = true,
  });

  final bool velocityBounce,
      arcs,
      directionalSquash,
      iconSpring,
      iconHop,
      labelSlide,
      navItemLag,
      rubberBand,
      impact,
      pressFeedback,
      stretchyPill,
      gooey,
      colorBlend,
      blobImpact,
      contentBlend;

  /// Used for "Reduce motion": only the shape change itself remains.
  static const none = BottomBarMotion(
    velocityBounce: false,
    arcs: false,
    directionalSquash: false,
    iconSpring: false,
    iconHop: false,
    labelSlide: false,
    navItemLag: false,
    rubberBand: false,
    impact: false,
    pressFeedback: false,
    stretchyPill: false,
    gooey: false,
    colorBlend: false,
    blobImpact: false,
    contentBlend: false,
  );

  /// Names for the debug panel.
  static const labels = {
    'velocityBounce': 'Bounce by speed',
    'arcs': 'Arc',
    'directionalSquash': 'Stretch along motion',
    'iconSpring': 'Icon has its own spring',
    'iconHop': 'Icon hop',
    'labelSlide': 'Labels slide in',
    'navItemLag': 'Navigation icons lag',
    'rubberBand': 'Rubber band',
    'impact': 'Impact on navigation bar',
    'pressFeedback': 'Press',
    'stretchyPill': 'Stretchy pill',
    'gooey': 'Gooey neck',
    'colorBlend': 'Colour blend',
    'blobImpact': 'Blob',
    'contentBlend': 'Content dissolves',
  };

  Map<String, bool> toMap() => {
        'velocityBounce': velocityBounce,
        'arcs': arcs,
        'directionalSquash': directionalSquash,
        'iconSpring': iconSpring,
        'iconHop': iconHop,
        'labelSlide': labelSlide,
        'navItemLag': navItemLag,
        'rubberBand': rubberBand,
        'impact': impact,
        'pressFeedback': pressFeedback,
        'stretchyPill': stretchyPill,
        'gooey': gooey,
        'colorBlend': colorBlend,
        'blobImpact': blobImpact,
        'contentBlend': contentBlend,
      };

  factory BottomBarMotion.fromMap(Map<String, bool> m) => BottomBarMotion(
        velocityBounce: m['velocityBounce'] ?? false,
        arcs: m['arcs'] ?? false,
        directionalSquash: m['directionalSquash'] ?? false,
        iconSpring: m['iconSpring'] ?? false,
        iconHop: m['iconHop'] ?? false,
        labelSlide: m['labelSlide'] ?? false,
        navItemLag: m['navItemLag'] ?? false,
        rubberBand: m['rubberBand'] ?? false,
        impact: m['impact'] ?? false,
        pressFeedback: m['pressFeedback'] ?? false,
        stretchyPill: m['stretchyPill'] ?? false,
        gooey: m['gooey'] ?? false,
        colorBlend: m['colorBlend'] ?? false,
        blobImpact: m['blobImpact'] ?? false,
        contentBlend: m['contentBlend'] ?? false,
      );
}
