// Minimal EmbedLite browser shell: sets up the embedding context the way
// qtmozembed's test runner does, then shows main.qml.
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTextStream>
#include <QQuickItem>
#include <QQuickView>
#include <QRegion>
#include <QWindow>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <cstdlib>
#include <unistd.h>
#include <xcb/xcb.h>
#include <mozilla/embedlite/EmbedLiteApp.h>
#include <qmozcontext.h>
#include <qmozwindow.h>
#include <qmozenginesettings.h>

// Keeps the window in hildon-desktop's compositor. hildon-desktop draws a
// full screen window that is not stackable straight to the screen (X page
// flips to the window's buffers) unless _HILDON_NON_COMPOSITED_WINDOW is 0,
// and switches it back into the compositor for its status menu, task
// switcher or an incoming call. After such a switch the panel went on
// showing an old picture of the shell, or black, until the display was
// reset. A window composited from the start is never flipped to. Set from a
// connection of its own, before Qt maps the window.
static void keepComposited(WId window)
{
    xcb_connection_t *c = xcb_connect(nullptr, nullptr);
    if (!xcb_connection_has_error(c)) {
        static const char name[] = "_HILDON_NON_COMPOSITED_WINDOW";
        xcb_intern_atom_reply_t *atom = xcb_intern_atom_reply(
            c, xcb_intern_atom(c, 0, sizeof name - 1, name), nullptr);
        if (atom) {
            const uint32_t composited = 0;
            xcb_change_property(c, XCB_PROP_MODE_REPLACE, window, atom->atom,
                                XCB_ATOM_INTEGER, 32, 1, &composited);
            free(atom);
        }
        // a round trip: the server has the property before the window maps
        free(xcb_get_input_focus_reply(c, xcb_get_input_focus(c), nullptr));
    }
    xcb_disconnect(c);
}

// Gecko draws the page straight into a native child window over the web view's
// area instead of handing each frame to Qt Quick as a texture: about 28 % less
// CPU per frame on the N950, and more frames while scrolling. The child lets
// input through to the view below it and leaves out the settings panel when
// that is open. EMBEDLITE_SHELL_DIRECT=0 goes back to the texture.
class ContentWindow : public QObject
{
public:
    ContentWindow(QQuickView &view)
        : mWindow(new QWindow(&view))
    {
        mWindow->setFlags(Qt::FramelessWindowHint | Qt::WindowTransparentForInput);
        // a plain X window: as an OpenGL surface Qt's EGL integration makes an
        // EGL surface of its own for it, and the driver refuses Gecko's second
        // one (EGL_BAD_ALLOC)
        mWindow->setSurfaceType(QSurface::RasterSurface);
        mWindow->setGeometry(0, 0, 1, 1);
        mWindow->create();
    }
    WId id() const { return mWindow->winId(); }
    void follow(QQuickItem *web, QQuickItem *panel)
    {
        mWeb = web;
        mPanel = panel;
        for (QQuickItem *item : {web, panel}) {
            if (!item) {
                continue;
            }
            connect(item, &QQuickItem::xChanged, this, &ContentWindow::update);
            connect(item, &QQuickItem::yChanged, this, &ContentWindow::update);
            connect(item, &QQuickItem::widthChanged, this, &ContentWindow::update);
            connect(item, &QQuickItem::heightChanged, this, &ContentWindow::update);
            connect(item, &QQuickItem::visibleChanged, this, &ContentWindow::update);
        }
        update();
        mWindow->show();
    }

private:
    void update()
    {
        const QRect area = mWeb->mapRectToScene(QRectF(0, 0, mWeb->width(), mWeb->height())).toRect();
        if (area.isEmpty()) {
            return;
        }
        mWindow->setGeometry(area);
        QRegion shown(0, 0, area.width(), area.height());
        if (mPanel && mPanel->isVisible()) {
            const QRect panel = mPanel->mapRectToScene(
                QRectF(0, 0, mPanel->width(), mPanel->height())).toRect();
            shown -= panel.translated(-area.topLeft());
        }
        if (shown != mWindow->mask()) {
            mWindow->setMask(shown);
            // what the panel covered is part of the window again: Gecko
            // draws all of it anew
            if (QMozWindow *mozWindow = QMozContext::instance()->registeredWindow()) {
                mozWindow->scheduleUpdate();
            }
        }
    }

    QWindow *mWindow;
    QQuickItem *mWeb = nullptr;
    QQuickItem *mPanel = nullptr;
};

static const char kComponents[] = "/usr/lib/arm-linux-gnueabihf/mozembedlite-next153";
static const char kProfile[] = "embedlite-shell";

// Prefs Gecko reads once at startup, in the profile's user.js: WebRender
// on the GPU (the SGX530 through its OpenGL ES 2.0 path) with compiled
// shader programs kept on disk, and edge anti-aliasing unless --no-edge-aa
// (jagged rotated edges, three times faster rotated content).
static void writeUserPrefs(bool edgeAa)
{
    const QString dir = QDir::homePath() + "/.mozilla/" + kProfile;
    QDir().mkpath(dir);
    QFile file(dir + "/user.js");
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return;
    QTextStream out(&file);
    // EmbedLite stores layers.acceleration.disabled in prefs.js; a value left
    // from an older engine that always ran in software must not win
    out << "user_pref(\"layers.acceleration.disabled\", false);\n"
        << "user_pref(\"layers.offmainthreadcomposition.force-basic\", false);\n"
        // a phone browser's user agent, so sites send their light mobile
        // pages (the N9's browser did the same with an Android one)
        << "user_pref(\"general.useragent.override\", \"Mozilla/5.0 (Android 10; "
           "Mobile; rv:153.0) Gecko/153.0 Firefox/153.0\");\n"
        // and the rest of what Firefox for Android reports, so that scripts
        // comparing navigator with the user agent (bot checks such as
        // Cloudflare's) see one consistent browser
        << "user_pref(\"general.platform.override\", \"Linux armv81\");\n"
        << "user_pref(\"general.oscpu.override\", \"Linux armv81\");\n"
        << "user_pref(\"general.appversion.override\", \"5.0 (Android 10)\");\n"
        << "user_pref(\"gfx.webrender.all\", true);\n"
        << "user_pref(\"gfx.webrender.software\", false);\n"
        << "user_pref(\"gfx.webrender.program-binary-disk\", true);\n"
        // glyphs and images through a staging texture, copied by draws into
        // the cache: on the SGX530 text stayed in place far more often
        << "user_pref(\"gfx.webrender.batched-texture-uploads\", true);\n"
        << "user_pref(\"gfx.webrender.draw-calls-for-texture-copy\", true);\n"
        << "user_pref(\"gfx.webrender.edge-aa\", " << (edgeAa ? "true" : "false") << ");\n"
        // full frames into the offscreen buffers Qt shows
        << "user_pref(\"gfx.webrender.max-partial-present-rects\", 0);\n";
}

// Stops CSS animations and transitions on every page: they jump to their
// end state at once (so pages waiting for them still go on).
static const char kNoMotionCss[] =
    "*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;"
    "animation-iteration-count:1!important;transition-duration:0s!important;"
    "transition-delay:0s!important;scroll-behavior:auto!important}";

// The shell's own switches, kept in ~/.config/embedlite-shell/settings.conf
// and pushed into the engine once it runs and whenever one changes.
// Animations are off unless switched on: on the N950, redrawing an animated
// page (a spinning loading indicator) took half the CPU away from scripts.
class ShellSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool animations READ animations WRITE setAnimations NOTIFY animationsChanged)

public:
    bool animations() const { return m_settings.value(QStringLiteral("animations"), false).toBool(); }
    void setAnimations(bool on)
    {
        if (on == animations())
            return;
        m_settings.setValue(QStringLiteral("animations"), on);
        apply();
        Q_EMIT animationsChanged();
    }

    void apply()
    {
        QMozContext *context = QMozContext::instance();
        if (!context->isInitialized())
            return;
        const bool on = animations();
        QMozEngineSettings *engine = QMozEngineSettings::instance();
        // the prefers-reduced-motion media query, which many sites honour
        engine->setPreference(QStringLiteral("ui.prefersReducedMotion"), on ? 0 : 1);
        engine->setPreference(QStringLiteral("image.animation_mode"),
                              on ? QStringLiteral("normal") : QStringLiteral("none"));
        if (m_noMotionSheet == on) {
            const QByteArray uri = "data:text/css," + QUrl::toPercentEncoding(QString::fromLatin1(kNoMotionCss));
            context->GetApp()->LoadGlobalStyleSheet(uri.constData(), !on);
            m_noMotionSheet = !on;
        }
    }

Q_SIGNALS:
    void animationsChanged();

private:
    QSettings m_settings{QStringLiteral("embedlite-shell"), QStringLiteral("settings")};
    bool m_noMotionSheet = false;
};

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QString start = QStringLiteral("about:blank");
    bool edgeAa = true;
    for (const QString &arg : app.arguments().mid(1)) {
        if (arg == QLatin1String("--no-edge-aa"))
            edgeAa = false;
        else
            start = arg;
    }
    writeUserPrefs(edgeAa);

    QMozContext *context = QMozContext::instance();
    context->setProfile(QString::fromLatin1(kProfile));
    const QString components = QString::fromLatin1(kComponents);
    context->addComponentManifest(components + "/components/EmbedLiteBinComponents.manifest");
    context->addComponentManifest(components + "/chrome/EmbedLiteJSScripts.manifest");
    context->addComponentManifest(components + "/chrome/EmbedLiteOverrides.manifest");
    context->addComponentManifest(components + "/components/EmbedLiteJSComponents.manifest");
    QObject::connect(context, &QMozContext::lastViewDestroyed, context, &QMozContext::stopEmbedding);
    QObject::connect(context, &QMozContext::contextDestroyed, &app, &QGuiApplication::quit);

    ShellSettings settings;
    QObject::connect(context, &QMozContext::initialized, &settings, &ShellSettings::apply);

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    // the toolbar's close button (Qt.quit()): the shell is full screen, so
    // its window goes at once; Gecko shuts down after the last view, and the
    // process ends at the latest 5 s (EMBEDLITE_SHELL_EXIT_GRACE) later
    const int grace = qEnvironmentVariableIsSet("EMBEDLITE_SHELL_EXIT_GRACE")
        ? qEnvironmentVariableIntValue("EMBEDLITE_SHELL_EXIT_GRACE") : 5;
    QObject::connect(view.engine(), &QQmlEngine::quit, &view, [&view, grace] {
        view.hide();
        view.setSource(QUrl());
        QTimer::singleShot(grace * 1000, [] { _exit(0); });
    }, Qt::QueuedConnection);
    // EMBEDLITE_SHELL_QUIT=<seconds>: quits as the close button does, after a
    // while; a PGO training run writes its profile only on a normal exit
    if (const int quitAfter = qEnvironmentVariableIntValue("EMBEDLITE_SHELL_QUIT"))
        QTimer::singleShot(quitAfter * 1000, view.engine(), &QQmlEngine::quit);
    view.rootContext()->setContextProperty(QStringLiteral("startUrl"), start);
    view.rootContext()->setContextProperty(QStringLiteral("shellSettings"), &settings);
    // EMBEDLITE_SHELL_SCROLLTEST=<seconds>:<swipes>: after a while, swipes up
    // over the page with synthetic touch input, one swipe every 2 s
    const QStringList scrollTest =
        qEnvironmentVariable("EMBEDLITE_SHELL_SCROLLTEST").split(':');
    view.rootContext()->setContextProperty(QStringLiteral("scrollTestStart"),
                                           scrollTest.value(0).toInt());
    view.rootContext()->setContextProperty(QStringLiteral("scrollTestSwipes"),
                                           scrollTest.value(1).toInt());
    view.rootContext()->setContextProperty(QStringLiteral("pinchTestStart"),
                                           qEnvironmentVariableIntValue("EMBEDLITE_SHELL_PINCHTEST"));
    const bool direct = !qEnvironmentVariableIsSet("EMBEDLITE_SHELL_DIRECT")
        || qEnvironmentVariableIntValue("EMBEDLITE_SHELL_DIRECT");
    ContentWindow *content = direct ? new ContentWindow(view) : nullptr;
    view.rootContext()->setContextProperty(QStringLiteral("contentWindow"),
                                           content ? qulonglong(content->id()) : qulonglong(0));

    QTimer::singleShot(0, [&] {
        context->runEmbedding();
        QMozEngineSettings::instance();
        view.setSource(QUrl(QStringLiteral("qrc:/main.qml")));
        if (content) {
            QQuickItem *root = view.rootObject();
            content->follow(root->findChild<QQuickItem *>(QStringLiteral("web")),
                            root->findChild<QQuickItem *>(QStringLiteral("settingsPanel")));
        }
        keepComposited(view.winId());
        view.showFullScreen();
    });
    // hildon-desktop sometimes took the window as a normal one although it
    // asked for full screen: its status area then lay over the toolbar and a
    // tap on the address field opened the status menu. Asking again once the
    // window is up makes it a full screen application.
    QTimer::singleShot(1500, &view, [&view] {
        view.setWindowState(Qt::WindowNoState);
        view.showFullScreen();
    });

    // EMBEDLITE_SHELL_GRAB=file.png[:seconds] saves what the window shows
    // (read back from GL) after a while. It does not contain the web view
    // when Gecko renders on the GPU; xwd -root does (display on).
    const QString grab = qEnvironmentVariable("EMBEDLITE_SHELL_GRAB");
    if (!grab.isEmpty()) {
        const int colon = grab.lastIndexOf(':');
        const QString file = colon > 0 ? grab.left(colon) : grab;
        const int seconds = colon > 0 ? grab.mid(colon + 1).toInt() : 60;
        QTimer::singleShot(seconds * 1000, [&view, file] { view.grabWindow().save(file); });
    }
    // EMBEDLITE_SHELL_FBDUMP=DIR: each frame Qt renders, read back from
    // its framebuffer into DIR/fb_N.ppm (N cycling 0-7)
    const QByteArray fbDump = qgetenv("EMBEDLITE_SHELL_FBDUMP");
    if (!fbDump.isEmpty()) {
        QObject::connect(&view, &QQuickWindow::afterRendering, &view, [&view, fbDump] {
            static int frame = 0;
            ++frame;
            const int w = view.width() * view.devicePixelRatio();
            const int h = view.height() * view.devicePixelRatio();
            QByteArray pixels(w * h * 4, 0);
            QOpenGLContext::currentContext()->functions()->glReadPixels(
                0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
            const QString path = QString::fromLocal8Bit(fbDump) + QStringLiteral("/fb_%1.ppm").arg(frame % 8);
            QFile file(path);
            if (file.open(QIODevice::WriteOnly)) {
                file.write(QStringLiteral("P6\n%1 %2\n255\n").arg(w).arg(h).toLatin1());
                for (int i = 0; i < w * h; ++i)
                    file.write(pixels.constData() + i * 4, 3);
            }
        }, Qt::DirectConnection);
    }
    return app.exec();
}

#include "main.moc"
