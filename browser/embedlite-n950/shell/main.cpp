// Minimal EmbedLite browser shell: sets up the embedding context the way
// qtmozembed's test runner does, then shows main.qml.
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QTimer>
#include <qmozcontext.h>
#include <qmozenginesettings.h>

static const char kComponents[] = "/usr/lib/arm-linux-gnueabihf/mozembedlite-next153";

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QString start = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QStringLiteral("about:blank");

    QMozContext *context = QMozContext::instance();
    context->setProfile(QStringLiteral("embedlite-shell"));
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

    QTimer::singleShot(0, [&] {
        context->runEmbedding();
        QMozEngineSettings::instance();
        view.setSource(QUrl(QStringLiteral("qrc:/main.qml")));
        view.showFullScreen();
    });
    return app.exec();
}
