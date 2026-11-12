// Minimal EmbedLite browser shell: sets up the embedding context the way
// qtmozembed's test runner does, then shows main.qml.
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QQmlContext>
#include <QTextStream>
#include <QQuickView>
#include <QTimer>
#include <qmozcontext.h>
#include <qmozenginesettings.h>

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
        << "user_pref(\"gfx.webrender.all\", true);\n"
        << "user_pref(\"gfx.webrender.software\", false);\n"
        << "user_pref(\"gfx.webrender.program-binary-disk\", true);\n"
        << "user_pref(\"gfx.webrender.edge-aa\", " << (edgeAa ? "true" : "false") << ");\n"
        // full frames into the offscreen buffers Qt shows
        << "user_pref(\"gfx.webrender.max-partial-present-rects\", 0);\n";
}

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

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty(QStringLiteral("startUrl"), start);
    // EMBEDLITE_SHELL_SCROLLTEST=<seconds>:<swipes>: after a while, swipes up
    // over the page with synthetic touch input, one swipe every 2 s
    const QStringList scrollTest =
        qEnvironmentVariable("EMBEDLITE_SHELL_SCROLLTEST").split(':');
    view.rootContext()->setContextProperty(QStringLiteral("scrollTestStart"),
                                           scrollTest.value(0).toInt());
    view.rootContext()->setContextProperty(QStringLiteral("scrollTestSwipes"),
                                           scrollTest.value(1).toInt());

    QTimer::singleShot(0, [&] {
        context->runEmbedding();
        QMozEngineSettings::instance();
        view.setSource(QUrl(QStringLiteral("qrc:/main.qml")));
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
    return app.exec();
}
